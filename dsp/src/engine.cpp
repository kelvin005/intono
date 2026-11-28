// libintono engine: streaming pipeline and the C API (include/intono/intono.h).
//
// Pipeline per hop (architecture doc, "Pipeline stages"):
//   DC blocker -> HP 150 Hz -> LP 4 kHz (per sample)
//   -> window of `window_size` -> RMS + adaptive noise gate
//   -> YIN -> octave guard -> centre pitch / vibrato (ADR 0001)
//   -> cents vs target in the selected tuning -> onset flag -> SPSC frame ring
//   -> one HopRecord per hop into an SPSC queue (ADR 0008)
//   -> worker thread owned by the engine: note tracker (fixed-lag HMM, ADR 0004) -> SPSC note ring.
// In inline mode (tests, CLI, parity tools: engine_internal.hpp) there is no thread and intono_process calls the tracker itself.
//
// Real-time rules: intono_process and intono_drone_render never allocate, lock, log or
// make syscalls. Everything is sized in intono_create.
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <new>
#include <system_error>
#include <thread>
#include <vector>

#if defined(__linux__) || defined(__ANDROID__) || defined(__APPLE__)
#include <pthread.h>
#endif

#include "intono/intono.h"
#include "drone.hpp"
#include "engine_internal.hpp"
#include "filters.hpp"
#include "notes_hmm.hpp"
#include "post.hpp"
#include "ring.hpp"
#include "score_cursor.hpp"
#include "tuning.hpp"
#include "yin.hpp"

// The audio thread shares these with the UI thread. If any were not lock-free the platform would silently
// fall back to a mutex, and intono_process would no longer be real-time safe. Fail the build instead.
static_assert(std::atomic<int>::is_always_lock_free && std::atomic<float>::is_always_lock_free &&
                  std::atomic<size_t>::is_always_lock_free && std::atomic<bool>::is_always_lock_free &&
                  std::atomic<uint64_t>::is_always_lock_free,
              "libintono needs lock-free atomics");

namespace {

constexpr double kYinThreshold = 0.12;
constexpr double kHighpassHz = 150.0, kLowpassHz = 4000.0;
constexpr double kGateLearnS = 0.5, kGateOpenDb = 10.0, kGateFloorCapDb = -50.0;
constexpr double kOnsetRiseDb = 6.0;
constexpr int kOnsetRefractoryFrames = 10;     // ~53 ms at 256/48000
constexpr double kPitchMoveCents = 50.0;
constexpr int kPitchMoveFrames = 6;            // ~30 ms at 256/48000
constexpr double kStepSpanCents = 50.0;        // a legato step smeared over a few frames: |raw[i] - raw[i-4]| over this ...
constexpr double kStepSettledCents = 15.0;     // ... and the pitch has stopped moving (last frame-to-frame change under this)
constexpr int kStepSpanFrames = 4;
constexpr int kResumeGapFrames = 20;           // a voicing dropout up to ~107 ms still belongs to the same phrase
constexpr int kNoteEndGapFrames = kResumeGapFrames;  // a note ends after more than this many unvoiced frames
constexpr int kNoteMinFrames = 10;             // ~53 ms; shorter runs are glitches
constexpr size_t kNoteRing = 64;
constexpr size_t kFrameRing = 1024;            // ~5.4 s of frames at 5.3 ms
constexpr size_t kRecordRing = 1024;           // ~5.4 s of hop records (ADR 0008), 1024 x 80 bytes
constexpr int kWorkerPollUs = 2000;            // the worker sleeps this long when the queue is empty (no wake-up call from the audio thread)

// What NoteTracker::update needs for one hop, plus the frame index (a gap means a dropped record) and the probe timestamp.
struct HopRecord {
  double t = 0.0, conf = 0.0, c = 0.0, vr = 0.0, vw = 0.0, ctr = 0.0, cents_a4 = 0.0;
  long long fidx = 0;
  int64_t push_ns = 0;   // steady clock at the push; 0 unless the probe is enabled
  bool voiced = false, rms_onset = false;
};

int64_t now_ns() { return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count(); }

}  // namespace

struct intono_engine {
  intono_config cfg;
  intono::Tuning tuning;
  int win, hop;
  double hop_s;

  intono::DcBlocker dc;
  intono::Biquad hp, lp;
  std::vector<float> hist;   // circular preprocessed samples (size win)
  std::vector<float> frame;  // contiguous analysis window
  int hpos = 0;
  long long total = 0, next_end = 0, fidx = 0;

  intono::Yin yin;
  intono::OctaveGuard guard;
  intono::CentreTracker centre;

  // adaptive noise gate
  std::vector<double> learn;
  int n_learn;
  double floor_db = kGateFloorCapDb;

  // onset state
  double db_prev[3] = {-200, -200, -200};
  int since_onset = 1000;
  double last_voiced_c = 0.0, pre_jump_c = 0.0;  // displayed centre (cents re 440 Hz)
  bool prev_voiced = false, have_last_c = false;
  int pending_move = 0, gap_frames = 1000;
  double raw_hist[kStepSpanFrames] = {}, disp_hist[kStepSpanFrames] = {};  // the previous 4 frames of the voiced run, newest last
  int hist_n = 0;

  intono::SpscRing<intono_frame> ring;
  intono::SpscRing<HopRecord> records{kRecordRing};   // audio thread -> worker
  intono::NoteTracker notes;                          // worker thread only (inline mode: audio thread)
  intono::SpscRing<intono_note> note_ring{kNoteRing}; // worker -> UI thread
  std::atomic<int> tonic{60};
  // ---- scale mode (ADR 0014) ----
  // UI -> worker handoff of the expected sequence: a seqlock (odd while the UI writes); the data are atomics so the handoff is
  // race-free without a lock. The worker (inline mode: the audio thread) picks a new sequence up between records.
  std::atomic<uint32_t> exp_seq{0};
  std::atomic<int> exp_n{0};
  std::atomic<int> exp_buf[intono::ScoreCursor::kMax];
  uint32_t exp_seen = 0;               // worker
  intono::ScoreCursor cursor;          // worker
  int exp_tmp[intono::ScoreCursor::kMax] = {};   // worker scratch
  intono::Drone drone;

  // ---- worker (ADR 0008) ----
  bool inline_mode = false;
  std::thread worker;
  std::atomic<bool> stop{false};
  uint64_t pushed = 0;                                // audio thread
  std::atomic<uint64_t> consumed{0};                  // worker
  long long prev_fidx = -1;                           // worker: previous record's frame index
  std::atomic<size_t> high_water{0};
  std::atomic<int> stall_max_us{0}, spin_ns{0};
  uint32_t stall_state = 1;                           // worker only
  bool probe_on = false;                              // audio thread, set before the first process
  std::vector<float> probe_lat_us, probe_work_us;     // preallocated by enable_probe; written by the worker only
  std::atomic<size_t> probe_n{0};

  explicit intono_engine(const intono_config& c)
      : cfg(c),
        tuning(static_cast<intono::Tuning>(c.tuning)),
        win(c.window_size),
        hop(c.hop_size),
        hop_s(static_cast<double>(c.hop_size) / c.sample_rate),
        hist(c.window_size, 0.f),
        frame(c.window_size, 0.f),
        yin(c.sample_rate, c.window_size, c.min_hz, c.max_hz, kYinThreshold),
        centre(static_cast<double>(c.hop_size) / c.sample_rate),
        ring(kFrameRing),
        notes(kNoteEndGapFrames, kNoteMinFrames, 0.5 * c.window_size / c.sample_rate),
        drone(c.sample_rate, c.a4_hz) {
    hp = intono::Biquad::butter2(true, kHighpassHz, c.sample_rate);
    lp = intono::Biquad::butter2(false, kLowpassHz, c.sample_rate);
    n_learn = std::max(1, static_cast<int>(kGateLearnS * c.sample_rate / c.hop_size));
    learn.assign(n_learn, 0.0);
    next_end = win;
  }

  void analyse() {
    for (int i = 0; i < win; ++i) frame[i] = hist[(hpos + i) % win];  // oldest sample sits at hpos

    double ms = 0.0;
    for (int i = 0; i < win; ++i) ms += static_cast<double>(frame[i]) * frame[i];
    ms /= win;
    const double db = 20.0 * std::log10(std::sqrt(ms + 1e-20) + 1e-12);

    if (fidx < n_learn) {
      learn[fidx] = db;
      if (fidx == n_learn - 1) {  // learning done: noise floor = 20th percentile, capped
        std::sort(learn.begin(), learn.end());
        const double p = 0.2 * (n_learn - 1);
        const int lo = static_cast<int>(std::floor(p));
        const int hi = std::min(lo + 1, n_learn - 1);
        floor_db = std::min(learn[lo] + (p - lo) * (learn[hi] - learn[lo]), kGateFloorCapDb);
      }
    }
    const bool gate_open = db > floor_db + kGateOpenDb;

    const intono::YinResult y = yin.analyze(frame.data());
    const bool voiced = y.found && gate_open;
    const double guarded = guard.update(voiced, y.hz, y.confidence);
    const intono::CentreOut c = centre.update(voiced, guarded);

    // onsets: RMS rise over 6 dB, or a pitch move over 50 cents held for ~30 ms
    bool onset = false;
    if (fidx >= 3 && gate_open && since_onset > kOnsetRefractoryFrames &&
        db - std::min({db_prev[0], db_prev[1], db_prev[2]}) > kOnsetRiseDb) {
      onset = true;
    }
    const bool rms_onset = onset;  // the note tracker splits on this one only; pitch moves are its HMM's business
    if (voiced && c.hz > 0.0 && guarded > 0.0) {
      const double disp_c = 1200.0 * std::log2(c.hz / 440.0);
      const double raw_c = 1200.0 * std::log2(guarded / 440.0);
      if (!prev_voiced) {
        // voicing resumed: a new note if it comes back over 50 c from where it left off
        // (legato note change through a one-frame dropout); after a long gap the RMS rise decides
        if (have_last_c && gap_frames <= kResumeGapFrames && std::fabs(disp_c - last_voiced_c) > kPitchMoveCents) onset = true;
        pending_move = 0;
      } else if (pending_move == 0) {
        // Two ways to notice that the pitch moved to a new note; either starts a ~30 ms confirmation.
        //  - the tracker saw a jump between consecutive frames (abrupt step), or
        //  - the pitch settled more than 50 c from where it was 4 frames ago: a legato step is smeared over about
        //    three frames by the 21 ms window, so a semitone can arrive in steps of 25 c, each under the jump rule.
        // It is an onset only if the new pitch stays over 50 c from the old note (a glitch or a slide does not).
        bool start = false;
        if (c.note_changed) {
          pre_jump_c = last_voiced_c;
          start = true;
        } else if (hist_n >= kStepSpanFrames && std::fabs(raw_c - raw_hist[kStepSpanFrames - 1]) < kStepSettledCents &&
                   std::fabs(raw_c - raw_hist[0]) > kStepSpanCents) {
          pre_jump_c = disp_hist[0];
          start = true;
        }
        pending_move = (start && std::fabs(raw_c - pre_jump_c) > kPitchMoveCents) ? kPitchMoveFrames - 1 : 0;
      } else {
        if (std::fabs(raw_c - pre_jump_c) > kPitchMoveCents) {
          if (--pending_move == 0) onset = true;
        } else {
          pending_move = 0;
        }
      }
      for (int k = 0; k + 1 < kStepSpanFrames; ++k) {
        raw_hist[k] = raw_hist[k + 1];
        disp_hist[k] = disp_hist[k + 1];
      }
      raw_hist[kStepSpanFrames - 1] = raw_c;
      disp_hist[kStepSpanFrames - 1] = disp_c;
      if (hist_n < kStepSpanFrames) ++hist_n;
      last_voiced_c = disp_c;
      have_last_c = true;
      gap_frames = 0;
      prev_voiced = true;
    } else {
      prev_voiced = false;
      pending_move = 0;
      hist_n = 0;
      if (gap_frames < 100000) ++gap_frames;
    }
    if (onset && since_onset <= kOnsetRefractoryFrames) onset = false;  // one onset per ~53 ms at most
    since_onset = onset ? 0 : since_onset + 1;
    db_prev[0] = db_prev[1];
    db_prev[1] = db_prev[2];
    db_prev[2] = db;

    intono_frame f{};
    f.t_sec = (static_cast<double>(fidx) * hop + win / 2.0) / cfg.sample_rate;
    f.confidence = static_cast<float>(y.confidence);
    f.is_voiced = voiced ? 1 : 0;
    f.is_onset = onset ? 1 : 0;
    if (voiced && c.hz > 0.0) {
      const intono::Target t = intono::nearest_target(c.hz, tuning, cfg.a4_hz, tonic.load(std::memory_order_relaxed));
      f.hz = static_cast<float>(c.hz);
      f.midi_note = t.midi_note;
      f.cents = static_cast<float>(t.cents);
      f.vibrato_rate_hz = static_cast<float>(c.vib_rate);
      f.vibrato_width_cents = static_cast<float>(c.vib_width);
    }
    {
      HopRecord r;
      r.t = f.t_sec;
      r.conf = y.confidence;
      r.voiced = voiced && c.hz > 0.0 && guarded > 0.0;
      r.rms_onset = rms_onset;
      r.fidx = fidx;
      if (r.voiced) {
        r.c = 1200.0 * std::log2(guarded / 440.0);
        r.cents_a4 = 1200.0 * std::log2(guarded / cfg.a4_hz);
        r.vr = c.vib_rate;
        r.vw = c.vib_width;
        r.ctr = 1200.0 * std::log2(c.hz / 440.0);
      }
      ++pushed;
      if (inline_mode) {
        track(r);
        consumed.fetch_add(1, std::memory_order_relaxed);
      } else {
        if (probe_on) r.push_ns = now_ns();
        records.push(r);   // full: dropped and counted, never blocks; the worker ends the run at the hole
      }
    }
    ring.push(f);  // drops (and counts) when the UI falls behind; never blocks
    ++fidx;
  }

  // UI thread only (intono_set_expected).
  void set_expected(const int* midi, int n) {
    const int m = (midi && n > 0) ? std::min(n, intono::ScoreCursor::kMax) : 0;
    const uint32_t s0 = exp_seq.load(std::memory_order_relaxed);
    exp_seq.store(s0 + 1, std::memory_order_relaxed);
    std::atomic_thread_fence(std::memory_order_release);
    for (int i = 0; i < m; ++i) exp_buf[i].store(midi[i], std::memory_order_relaxed);
    exp_n.store(m, std::memory_order_relaxed);
    exp_seq.store(s0 + 2, std::memory_order_release);
  }

  // Worker: take a new expected sequence if the UI published one (a torn read is retried at the next record), then give the tracker
  // the steps ahead of the cursor. Free mode: no pairs, so the tracker decodes exactly as before ADR 0014.
  void refresh_bias(bool poll) {
    if (poll) {
      const uint32_t s1 = exp_seq.load(std::memory_order_acquire);
      if (s1 != exp_seen && (s1 & 1u) == 0) {
        const int m = exp_n.load(std::memory_order_relaxed);
        for (int i = 0; i < m; ++i) exp_tmp[i] = exp_buf[i].load(std::memory_order_relaxed);
        std::atomic_thread_fence(std::memory_order_acquire);
        if (exp_seq.load(std::memory_order_relaxed) == s1) {
          exp_seen = s1;
          cursor.set(exp_tmp, m);
        }
      }
    }
    int from[intono::ScoreCursor::kAhead], to[intono::ScoreCursor::kAhead];
    const int np = cursor.pairs(from, to);
    notes.set_bias(from, to, np);
  }

  // One hop through the note tracker. Runs on the worker (or on the audio thread in inline mode).
  void track(const HopRecord& r) {
    refresh_bias(true);
    intono::NoteSummary ns[intono::NoteTracker::kMaxOut];
    if (prev_fidx >= 0 && r.fidx != prev_fidx + 1) {   // a record was dropped: no frame may be carried across the hole
      const int g = notes.flush(ns);
      for (int i = 0; i < g; ++i) emit_note(ns[i]);
    }
    prev_fidx = r.fidx;
    intono::NoteFrame nf;
    nf.t = r.t;
    nf.conf = r.conf;
    if (r.voiced) {
      nf.c = r.c;
      nf.vr = r.vr;
      nf.vw = r.vw;
      nf.ctr = r.ctr;
    }
    const int got = notes.update(r.voiced, r.rms_onset, nf, r.cents_a4, ns);
    for (int i = 0; i < got; ++i) emit_note(ns[i]);
    if (got > 0) refresh_bias(false);   // the cursor moved: the next frame decodes with the new steps
  }

  void worker_main() {
#if defined(__linux__) || defined(__ANDROID__)
    pthread_setname_np(pthread_self(), "intono-notes");
#elif defined(__APPLE__)
    pthread_setname_np("intono-notes");
#endif
    HopRecord r;
    while (!stop.load(std::memory_order_acquire)) {
      const size_t depth = records.size();
      if (depth > high_water.load(std::memory_order_relaxed)) high_water.store(depth, std::memory_order_relaxed);
      if (!records.pop(r)) {
        std::this_thread::sleep_for(std::chrono::microseconds(kWorkerPollUs));
        continue;
      }
      const int sm = stall_max_us.load(std::memory_order_relaxed);
      if (sm > 0) {   // test hook: random stalls, to prove the output does not depend on the worker's timing
        stall_state = stall_state * 1664525u + 1013904223u;
        std::this_thread::sleep_for(std::chrono::microseconds((stall_state >> 8) % (static_cast<uint32_t>(sm) + 1)));
      }
      const int64_t t0 = r.push_ns ? now_ns() : 0;
      const int sp = spin_ns.load(std::memory_order_relaxed);
      if (sp > 0) {
        const int64_t until = now_ns() + sp;
        while (now_ns() < until) {}
      }
      track(r);
      if (r.push_ns) {
        const int64_t t1 = now_ns();
        const size_t k = probe_n.load(std::memory_order_relaxed);
        if (k < probe_lat_us.size()) {
          probe_lat_us[k] = static_cast<float>((t1 - r.push_ns) * 1e-3);
          probe_work_us[k] = static_cast<float>((t1 - t0) * 1e-3);
          probe_n.store(k + 1, std::memory_order_release);
        }
      }
      consumed.fetch_add(1, std::memory_order_release);
    }
  }

  ~intono_engine() {   // signal, join, then the members go (the worker uses them)
    stop.store(true, std::memory_order_release);
    if (worker.joinable()) worker.join();
  }

  void emit_note(const intono::NoteSummary& ns) {
    const double hz = 440.0 * std::exp2(ns.mean_c / 1200.0);
    const int tonic_midi = tonic.load(std::memory_order_relaxed);
    intono::Target t = intono::nearest_target(hz, tuning, cfg.a4_hz, tonic_midi);
    // Scale mode (ADR 0018): a note whose mean is within kScaleLabelWindow of a note that is due (expected[k] or expected[k+1]) is that
    // note, even if another semitone is nearer: a note played 36 cents sharp with vibrato has a mean that wanders past the +-50 cent
    // boundary. Free mode (cursor plain): the nearest target, as before.
    if (cursor.due(0) >= 0 && t.midi_note != cursor.due(0) && t.midi_note != cursor.due(1)) {
      double best = intono::kScaleLabelWindow + 1.0;
      intono::Target pick;
      for (int i = 0; i < 2; ++i) {
        const int d = cursor.due(i);
        if (d < 0) continue;
        const intono::Target c = intono::target_for_midi(hz, tuning, cfg.a4_hz, tonic_midi, d);
        if (c.hz > 0.0 && std::fabs(c.cents) <= intono::kScaleLabelWindow && std::fabs(c.cents) < best) {
          best = std::fabs(c.cents);
          pick = c;
        }
      }
      if (pick.hz > 0.0) t = pick;
    }
    intono_note n{};
    n.t_start = ns.t_start;
    n.t_end = ns.t_end;
    n.midi_note = t.midi_note;
    n.mean_cents = static_cast<float>(t.cents);
    n.std_cents = static_cast<float>(ns.std_c);
    n.vibrato_rate_hz = static_cast<float>(ns.vib_rate);
    n.vibrato_width_cents = static_cast<float>(ns.vib_width);
    n.mean_confidence = static_cast<float>(ns.mean_conf);
    n.frame_count = ns.frames;
    cursor.on_note(n.midi_note);   // scale mode (ADR 0014); no-op in free mode
    note_ring.push(n);
  }

  void process(const float* in, int n) {
    for (int i = 0; i < n; ++i) {
      double x = dc.process(in[i]);
      x = hp.process(x);
      x = lp.process(x);
      hist[hpos] = intono::flush_sample(static_cast<float>(x));
      hpos = (hpos + 1) % win;
      if (++total == next_end) {
        analyse();
        next_end += hop;
      }
    }
  }
};

static bool config_valid(const intono_config* c) {
  if (!c) return false;
  if (!(c->sample_rate >= 8000.f && c->sample_rate <= 192000.f)) return false;
  if (c->window_size < 64 || c->hop_size < 1 || c->hop_size > c->window_size) return false;
  if (!(c->a4_hz >= 400.f && c->a4_hz <= 480.f)) return false;
  if (c->tuning < 0 || c->tuning > 2) return false;
  if (!(c->min_hz > 20.f && c->min_hz < c->max_hz && c->max_hz < c->sample_rate / 4.f)) return false;
  return true;
}

namespace intono_internal {

intono_engine* create(const intono_config* cfg, bool inline_mode) {
  if (!config_valid(cfg)) return nullptr;
  intono_engine* e = nullptr;
  try {
    e = new intono_engine(*cfg);
    if (!e->yin.ok()) {  // window too short for min_hz
      delete e;
      return nullptr;
    }
    e->inline_mode = inline_mode;
    if (!inline_mode) e->worker = std::thread([e] { e->worker_main(); });   // allocation and thread creation: not real-time, allowed here
    return e;
  } catch (const std::bad_alloc&) {
  } catch (const std::system_error&) {   // the worker thread could not be created
  }
  delete e;   // ~intono_engine joins a worker that did start (none can have, on this path)
  return nullptr;
}

void drain(intono_engine* e) {
  if (!e || e->inline_mode) return;
  while (e->consumed.load(std::memory_order_acquire) + e->records.dropped() < e->pushed) std::this_thread::sleep_for(std::chrono::microseconds(50));
}
uint64_t dropped_records(const intono_engine* e) { return e ? e->records.dropped() : 0; }
size_t queue_depth(const intono_engine* e) { return e ? e->records.size() : 0; }
size_t queue_high_water(const intono_engine* e) { return e ? e->high_water.load() : 0; }
void reset_queue_high_water(intono_engine* e) { if (e) e->high_water.store(0); }
void set_worker_stall(intono_engine* e, int max_us, uint32_t seed) {
  if (!e) return;
  e->stall_state = seed ? seed : 1;
  e->stall_max_us.store(max_us);
}
void set_worker_spin_ns(intono_engine* e, int ns) { if (e) e->spin_ns.store(ns); }
void enable_probe(intono_engine* e, size_t cap) {
  if (!e || e->inline_mode) return;
  e->probe_lat_us.assign(cap, 0.f);
  e->probe_work_us.assign(cap, 0.f);
  e->probe_on = true;
}
ProbeStats probe_stats(intono_engine* e) {
  ProbeStats s;
  if (!e) return s;
  drain(e);
  s.n = e->probe_n.load(std::memory_order_acquire);
  if (!s.n) return s;
  std::vector<float> lat(e->probe_lat_us.begin(), e->probe_lat_us.begin() + s.n);
  double sl = 0, sw = 0;
  for (size_t i = 0; i < s.n; ++i) {
    sl += lat[i];
    sw += e->probe_work_us[i];
    s.work_max_us = std::max<double>(s.work_max_us, e->probe_work_us[i]);
  }
  std::sort(lat.begin(), lat.end());
  s.latency_mean_us = sl / s.n;
  s.latency_p99_us = lat[std::min(s.n - 1, static_cast<size_t>(0.99 * s.n))];
  s.latency_max_us = lat.back();
  s.work_mean_us = sw / s.n;
  return s;
}

}  // namespace intono_internal

extern "C" {

intono_engine* intono_create(const intono_config* cfg) { return intono_internal::create(cfg, false); }

void intono_process(intono_engine* e, const float* in, int n) {
  if (e && in && n > 0) e->process(in, n);
}

int intono_read_frames(intono_engine* e, intono_frame* out, int max) {
  if (!e || !out || max <= 0) return 0;
  int n = 0;
  while (n < max && e->ring.pop(out[n])) ++n;
  return n;
}

int intono_read_notes(intono_engine* e, intono_note* out, int max) {
  if (!e || !out || max <= 0) return 0;
  int n = 0;
  while (n < max && e->note_ring.pop(out[n])) ++n;
  return n;
}

void intono_set_tonic(intono_engine* e, int midi_note) {
  if (e) e->tonic.store(midi_note, std::memory_order_relaxed);
}

void intono_set_expected(intono_engine* e, const int* midi_notes, int n) {
  if (e) e->set_expected(midi_notes, n);
}

void intono_drone_set(intono_engine* e, int midi_note, float gain, int timbre) {
  if (e) e->drone.set(midi_note, gain, timbre);
}

void intono_drone_render(intono_engine* e, float* out, int n) {
  if (!e || !out || n <= 0) return;
  e->drone.render(out, n);
}

void intono_destroy(intono_engine* e) { delete e; }

}  // extern "C"
