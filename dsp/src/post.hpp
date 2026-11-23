// Post-processing after YIN: octave guard and the ADR 0001 centre-pitch / vibrato tracker.
// Direct streaming ports of tools/accuracy/ref/yin_ref.py (octave_guard, centre_pitch_extrema).
// Constructors allocate; update() never does.
#pragma once
#include <algorithm>
#include <cmath>
#include <vector>

namespace intono {

// Reject a jump to ~2x or ~0.5x the last stable pitch unless confidence stays above
// `conf` for `frames` consecutive frames; otherwise fold the estimate back an octave.
class OctaveGuard {
 public:
  explicit OctaveGuard(double conf = 0.9, int frames = 3) : conf_(conf), frames_(frames) {}
  double update(bool voiced, double hz, double confidence) {
    if (!voiced) {
      streak_ = 0;
      last_ = 0.0;
      return 0.0;
    }
    if (last_ > 0.0) {
      const double lr = std::log2(hz / last_);
      if (std::fabs(lr - 1.0) < 0.08 || std::fabs(lr + 1.0) < 0.08) {
        streak_ = confidence > conf_ ? streak_ + 1 : 0;
        if (streak_ >= frames_) {
          last_ = hz;
          streak_ = 0;
          return hz;
        }
        return hz / std::exp2(std::round(lr));  // hold the established octave
      }
      streak_ = 0;
    }
    last_ = hz;
    return hz;
  }
  void reset() { last_ = 0.0; streak_ = 0; }

 private:
  double conf_;
  int frames_;
  double last_ = 0.0;
  int streak_ = 0;
};

struct CentreParams {
  double contour_s = 0.25;       // pitch contour length
  double default_s = 0.15;       // median window when no vibrato is present
  double min_swing_c = 8.0;      // an extremum needs this much swing to count (noise guard)
  double vib_min_c = 10.0, vib_max_c = 100.0;   // accepted vibrato extent (peak to peak)
  double vib_min_hz = 3.5, vib_max_hz = 9.0;    // accepted vibrato rate
  double note_step_c = 30.0;     // frame-to-frame jump that starts a new note (steepest vibrato moves ~13 c/frame)
  // Slide following (ADR 0001, amendment 2): a portamento must be followed, not held at the old centre.
  double slide_margin_c = 15.0;  // established vibrato: raw pitch this far outside the last peak/trough = slide ...
  int slide_persist = 2;         // ... for this many frames in a row (one noisy frame is not a slide)
  double flat_range_c = 12.0;    // steady note: contour range up to this counts as flat ...
  double slide_dev_c = 25.0;     // ... and a departure this far from it counts as a slide
  int flat_min_frames = 12;      // frames of history needed before the steady-note rule applies
  int recent_frames = 6;         // newest frames excluded when judging the "previous" contour (a 7 c/frame slide leaves "flat" within 2)
  int follow_frames = 4;         // follow mode shows the median of this many newest frames
  int settle_frames = 20;        // follow mode ends when this many newest frames are flat (longer than a vibrato lingers at a turning point)
};

struct CentreOut {
  double hz = 0.0;       // displayed pitch (0 when unvoiced)
  double vib_rate = 0.0; // 0 when no vibrato
  double vib_width = 0.0;
  bool note_changed = false;  // true on the frame where a >note_step_c jump restarted the contour
};

class CentreTracker {
 public:
  CentreTracker(double hop_s, const CentreParams& p = CentreParams()) : hop_s_(hop_s), p_(p) {
    n_ctx_ = std::max(1, static_cast<int>(std::lround(p.contour_s / hop_s)));
    n_def_ = std::max(1, static_cast<int>(std::lround(p.default_s / hop_s)));
    ring_.assign(n_ctx_, 0.0);
    seg_.assign(n_ctx_, 0.0);
    sm_.assign(n_ctx_, 0.0);
    med_.assign(std::max(n_def_, 1), 0.0);
    ext_idx_.assign(n_ctx_ + 2, 0);
    ext_max_.assign(n_ctx_ + 2, 0);
  }

  CentreOut update(bool voiced, double hz) {
    CentreOut out;
    if (!voiced || hz <= 0.0) {
      run_len_ = 0;
      held_ = false;
      follow_ = false;
      have_env_ = false;
      outside_count_ = 0;
      return out;
    }
    const double cents = 1200.0 * std::log2(hz / 440.0);
    if (run_len_ > 0 && std::fabs(cents - last_cents_) > p_.note_step_c) {
      // Note change without a gap (ADR 0001): drop the old contour and the hold-over so no stale
      // centre or vibrato is shown for the new note.
      run_len_ = 0;
      held_ = false;
      follow_ = false;
      have_env_ = false;
      outside_count_ = 0;
      out.note_changed = true;
    }
    last_cents_ = cents;
    ring_[pos_] = cents;
    pos_ = (pos_ + 1) % n_ctx_;
    ++run_len_;

    int seg_len = std::min(run_len_, n_ctx_);
    for (int i = 0; i < seg_len; ++i) seg_[i] = ring_[(pos_ - seg_len + i + 2 * n_ctx_) % n_ctx_];

    // Slide detection. A slide leaves the model that describes the current note.
    if (!follow_) {
      bool slide = false;
      if (held_ && have_env_) {
        const bool outside = cents > env_hi_ + p_.slide_margin_c || cents < env_lo_ - p_.slide_margin_c;
        outside_count_ = outside ? outside_count_ + 1 : 0;
        slide = outside_count_ >= p_.slide_persist;
      } else if (seg_len >= p_.flat_min_frames) {
        const int m = seg_len - p_.recent_frames;  // contour before the newest frames
        double lo = seg_[0], hi = seg_[0];
        for (int i = 1; i < m; ++i) { lo = std::min(lo, seg_[i]); hi = std::max(hi, seg_[i]); }
        slide = (hi - lo <= p_.flat_range_c) && std::fabs(cents - 0.5 * (lo + hi)) > p_.slide_dev_c;
      }
      if (slide) {
        follow_ = true;
        held_ = false;
        have_env_ = false;
        outside_count_ = 0;
        const int keep = std::min(seg_len, p_.follow_frames);  // forget the old pitch, keep the newest frames
        for (int i = 0; i < keep; ++i) seg_[i] = seg_[seg_len - keep + i];
        seg_len = keep;
        run_len_ = keep;
      }
    }

    bool have = false;
    double centre = 0.0, vr = 0.0, vw = 0.0;
    if (seg_len >= 9) {
      const int m = seg_len - 2;
      for (int j = 0; j < m; ++j) sm_[j] = (seg_[j] + seg_[j + 1] + seg_[j + 2]) / 3.0;
      const int ne = zigzag(m);
      if (ne >= 2) {
        const int first = std::max(0, ne - 4);
        double sum = 0.0, lo = 1e30, hi = -1e30;
        int cnt = 0;
        for (int e = first; e + 1 < ne; ++e, ++cnt) sum += 0.5 * (sm_[ext_idx_[e]] + sm_[ext_idx_[e + 1]]);
        for (int e = first; e < ne; ++e) { lo = std::min(lo, sm_[ext_idx_[e]]); hi = std::max(hi, sm_[ext_idx_[e]]); }
        const double swing = std::fabs(sm_[ext_idx_[ne - 1]] - sm_[ext_idx_[ne - 2]]);
        const double half = (ext_idx_[ne - 1] - ext_idx_[ne - 2]) * hop_s_;
        const double rate = 1.0 / (2.0 * half);
        if (swing >= p_.vib_min_c && swing <= p_.vib_max_c && rate >= p_.vib_min_hz && rate <= p_.vib_max_hz) {
          have = true;
          centre = sum / cnt;
          vr = rate;
          vw = swing;
          env_lo_ = lo;
          env_hi_ = hi;
        }
      }
    }
    if (have) {
      follow_ = false;
      have_env_ = true;
      held_ = true; held_n_ = 0; hc_ = centre; hvr_ = vr; hvw_ = vw;
    } else if (follow_) {
      if (seg_len >= p_.settle_frames) {  // flat again: the slide is over
        double lo = seg_[seg_len - 1], hi = lo;
        for (int i = seg_len - p_.settle_frames; i < seg_len; ++i) { lo = std::min(lo, seg_[i]); hi = std::max(hi, seg_[i]); }
        if (hi - lo <= p_.flat_range_c) {
          follow_ = false;
          seg_len = p_.settle_frames;     // the slide frames must not leak into the new note's median
          run_len_ = p_.settle_frames;
        }
      }
    }
    if (!have && follow_) {
      const int n = std::min(seg_len, p_.follow_frames);
      for (int i = 0; i < n; ++i) med_[i] = seg_[seg_len - n + i];
      std::sort(med_.begin(), med_.begin() + n);
      centre = (n % 2) ? med_[n / 2] : 0.5 * (med_[n / 2 - 1] + med_[n / 2]);
      vr = vw = 0.0;
    } else if (!have && held_ && held_n_ < n_ctx_ && run_len_ > 1) {
      // Vibrato was established a moment ago but the latest extremum is not confirmed yet
      // (it needs a min_swing excursion back): hold the previous centre.
      centre = hc_; vr = hvr_; vw = hvw_;
      ++held_n_;
    } else if (!have) {
      held_ = false;
      have_env_ = false;
      const int n = std::min(run_len_, n_def_);
      for (int i = 0; i < n; ++i) med_[i] = seg_[seg_len - n + i];
      std::sort(med_.begin(), med_.begin() + n);
      centre = (n % 2) ? med_[n / 2] : 0.5 * (med_[n / 2 - 1] + med_[n / 2]);
      vr = vw = 0.0;
    }
    out.hz = 440.0 * std::exp2(centre / 1200.0);
    out.vib_rate = vr;
    out.vib_width = vw;
    return out;
  }

  int contour_frames() const { return n_ctx_; }

 private:
  // Alternating peaks/troughs of sm_[0..m) whose swing is >= min_swing; segment edges
  // are never extrema. Fills ext_idx_/ext_max_, returns the count.
  int zigzag(int m) {
    int ne = 0, hi = 0, lo = 0, mode = 0, cand = 0;
    const double s = p_.min_swing_c;
    for (int i = 1; i < m; ++i) {
      const double v = sm_[i];
      if (mode == 0) {
        if (v > sm_[hi]) hi = i;
        if (v < sm_[lo]) lo = i;
        if (v - sm_[lo] >= s) { mode = 1; cand = i; }
        else if (sm_[hi] - v >= s) { mode = -1; cand = i; }
      } else if (mode == 1) {
        if (v > sm_[cand]) cand = i;
        else if (sm_[cand] - v >= s) { ext_idx_[ne] = cand; ext_max_[ne++] = 1; mode = -1; cand = i; }
      } else {
        if (v < sm_[cand]) cand = i;
        else if (v - sm_[cand] >= s) { ext_idx_[ne] = cand; ext_max_[ne++] = 0; mode = 1; cand = i; }
      }
    }
    return ne;
  }

  double hop_s_;
  CentreParams p_;
  int n_ctx_ = 1, n_def_ = 1;
  std::vector<double> ring_, seg_, sm_, med_;
  std::vector<int> ext_idx_, ext_max_;
  int pos_ = 0, run_len_ = 0, held_n_ = 0;
  bool held_ = false, follow_ = false, have_env_ = false;
  int outside_count_ = 0;
  double hc_ = 0, hvr_ = 0, hvw_ = 0, last_cents_ = 0, env_lo_ = 0, env_hi_ = 0;
};

}  // namespace intono
