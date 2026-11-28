#include "audio_pump.hpp"

#include <algorithm>
#include <bit>
#include <chrono>
#include <cmath>
#include <cstring>

namespace intono_shim {

namespace {
void engine_process(void* c, const float* in, int n) { intono_process(static_cast<intono_engine*>(c), in, n); }
void engine_drone(void* c, float* out, int n) { intono_drone_render(static_cast<intono_engine*>(c), out, n); }
void null_process(void*, const float*, int) {}
void null_drone(void*, float* out, int n) { std::memset(out, 0, sizeof(float) * static_cast<size_t>(n)); }

// Log histogram: values below 16 ns have their own bucket; above, 16 buckets per octave.
int bucket_of(uint64_t ns) {
  if (ns < 16) return static_cast<int>(ns);
  const int oct = static_cast<int>(std::bit_width(ns)) - 1;                  // >= 4
  const int mant = static_cast<int>((ns >> (oct - 4)) & 15u);
  return std::min(detail::Timing::kBuckets - 1, 16 + (oct - 4) * 16 + mant);
}
double bucket_upper(int idx) {
  if (idx < 16) return static_cast<double>(idx + 1);
  const int oct = 4 + (idx - 16) / 16, mant = (idx - 16) % 16;
  return static_cast<double>((16 + mant + 1)) * static_cast<double>(1ULL << (oct - 4));
}
}  // namespace

EngineOps engine_ops(intono_engine* e) {
  if (!e) return EngineOps{nullptr, &null_process, &null_drone};
  return EngineOps{e, &engine_process, &engine_drone};
}

namespace detail {
void Timing::add(int64_t ns) {
  const uint64_t v = ns < 0 ? 0 : static_cast<uint64_t>(ns);
  count_.store(count_.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
  sum_.store(sum_.load(std::memory_order_relaxed) + v, std::memory_order_relaxed);
  if (v > max_.load(std::memory_order_relaxed)) max_.store(v, std::memory_order_relaxed);
  auto& h = hist_[bucket_of(v)];
  h.store(h.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
}

void Timing::clear() {
  count_.store(0, std::memory_order_relaxed);
  sum_.store(0, std::memory_order_relaxed);
  max_.store(0, std::memory_order_relaxed);
  for (auto& h : hist_) h.store(0, std::memory_order_relaxed);
}

TimingSummary Timing::summary() const {
  TimingSummary s;
  s.count = count_.load(std::memory_order_relaxed);
  if (s.count == 0) return s;
  s.mean_ns = static_cast<double>(sum_.load(std::memory_order_relaxed)) / static_cast<double>(s.count);
  s.max_ns = static_cast<double>(max_.load(std::memory_order_relaxed));
  auto quantile = [&](double q) {
    const uint64_t want = std::max<uint64_t>(1, static_cast<uint64_t>(std::ceil(q * static_cast<double>(s.count))));
    uint64_t acc = 0;
    for (int i = 0; i < kBuckets; ++i) {
      acc += hist_[i].load(std::memory_order_relaxed);
      if (acc >= want) return std::min(bucket_upper(i), s.max_ns);   // never report above the observed maximum
    }
    return s.max_ns;
  };
  s.p50_ns = quantile(0.50);
  s.p99_ns = quantile(0.99);
  return s;
}
}  // namespace detail

namespace {
constexpr uint64_t kValueMask = (1ULL << 23) - 1;
constexpr uint64_t kFlagBit = 1ULL << 23;
constexpr uint64_t kTimeMask = (1ULL << 40) - 1;
}  // namespace

namespace detail {
void EventRing::push(int64_t t_us, uint64_t value, bool flag) {
  const uint64_t c = count_.load(std::memory_order_relaxed);
  const uint64_t packed = ((static_cast<uint64_t>(t_us < 0 ? 0 : t_us) & kTimeMask) << 24) | (flag ? kFlagBit : 0) | std::min(value, kValueMask);
  slots_[c % kCap].store(packed, std::memory_order_relaxed);
  count_.store(c + 1, std::memory_order_release);
}

std::vector<EventRing::Item> EventRing::read() const {
  std::vector<Item> out;
  const uint64_t c = count_.load(std::memory_order_acquire);
  const uint64_t n = std::min<uint64_t>(c, kCap);
  out.reserve(static_cast<size_t>(n));
  for (uint64_t i = c - n; i < c; ++i) {
    const uint64_t v = slots_[i % kCap].load(std::memory_order_relaxed);
    out.push_back(Item{static_cast<int64_t>(v >> 24), v & kValueMask, (v & kFlagBit) != 0});
  }
  return out;
}
}  // namespace detail

AudioPump::AudioPump(EngineOps ops, PumpConfig cfg, Clock clock) : ops_(ops), cfg_(cfg), clock_(clock) {
  if (cfg_.hop_size < 1) cfg_.hop_size = 1;
  if (cfg_.sample_rate < 1) cfg_.sample_rate = 48000;
  epoch_ns_.store(now(), std::memory_order_relaxed);
}

int64_t AudioPump::now() const {
  if (clock_.now) return clock_.now(clock_.ctx);
  return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

void AudioPump::on_input(const float* in, int n, InputInfo info) {
  if (!in || n <= 0) return;
  if (replay_.frozen()) {   // review (ADR 0013): the microphone reaches neither the engine nor the ring
    was_paused_ = true;
    return;
  }
  if (was_paused_) {   // the paused stretch is not a gap: timing and position tracking start afresh
    was_paused_ = false;
    prev_n_ = 0;
    pos_seen_ = pos_valid_ = false;
  }
  const int64_t t0 = now();
  if (reset_in_.exchange(false, std::memory_order_acq_rel)) {
    chunk_.clear();
    callback_.clear();
    in_callbacks_.store(0, std::memory_order_relaxed);
    in_frames_.store(0, std::memory_order_relaxed);
    late_.store(0, std::memory_order_relaxed);
    in_gaps_.store(0, std::memory_order_relaxed);
    gap_frames_.store(0, std::memory_order_relaxed);
    overruns_.store(0, std::memory_order_relaxed);
    slow_.store(0, std::memory_order_relaxed);
    position_supported_.store(false, std::memory_order_relaxed);
    late_ring_.clear();
    gap_ring_.clear();
    slow_ring_.clear();
    epoch_ns_.store(t0, std::memory_order_relaxed);
    prev_n_ = 0;
    pos_seen_ = pos_valid_ = false;
    xr_seen_ = false;
  }
  const int64_t epoch = epoch_ns_.load(std::memory_order_relaxed);
  if (prev_n_ > 0) {
    const double expected_ns = 1e9 * static_cast<double>(prev_n_) / static_cast<double>(cfg_.sample_rate);
    const double dt = static_cast<double>(t0 - prev_start_ns_);
    if (dt > cfg_.gap_factor * expected_ns) {
      late_.store(late_.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
      late_ring_.push((t0 - epoch) / 1000, static_cast<uint64_t>((dt - expected_ns) / 1000.0));
    }
  }
  prev_start_ns_ = t0;
  prev_n_ = n;
  note_position(info, n, t0);

  if (ops_.process) {
    int done = 0;
    while (done < n) {
      const int m = std::min(cfg_.hop_size, n - done);
      const int64_t a = now();
      ops_.process(ops_.ctx, in + done, m);
      const int64_t cost = now() - a;
      chunk_.add(cost);
      if (cost > cfg_.slow_hop_ns) {
        slow_.store(slow_.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
        slow_ring_.push((a - epoch) / 1000, static_cast<uint64_t>(cost / 1000));
      }
      done += m;
    }
  }
  replay_.on_input(in, n);   // counts every frame (the engine's clock); keeps it only while armed
  callback_.add(now() - t0);
  in_callbacks_.store(in_callbacks_.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
  in_frames_.store(in_frames_.load(std::memory_order_relaxed) + static_cast<uint64_t>(n), std::memory_order_relaxed);
}

void AudioPump::note_position(const InputInfo& info, int n, int64_t t0) {
  const int64_t epoch = epoch_ns_.load(std::memory_order_relaxed);
  const int64_t delivered = static_cast<int64_t>(in_frames_.load(std::memory_order_relaxed));   // frames passed to the pump before this callback

  if (info.xruns >= 0) {
    if (!xr_seen_) {
      xr_seen_ = true;
      xr_base_ = xr_prev_ = info.xruns;
    } else if (info.xruns > xr_prev_) {
      overruns_.store(static_cast<uint64_t>(info.xruns - xr_base_), std::memory_order_relaxed);
      gap_ring_.push((t0 - epoch) / 1000, static_cast<uint64_t>(info.xruns - xr_prev_), true);
      xr_prev_ = info.xruns;
    }
  }

  if (info.position < 0) return;
  const int64_t a = info.position - delivered;   // offset under convention A
  const int64_t b = a - n;                       // offset under convention B
  if (!pos_seen_) {
    pos_seen_ = true;
    pos_first_ = info.position;
    off_a_ = a;
    off_b_ = b;
    chg_a_ = chg_b_ = 0;
    return;
  }
  if (!pos_valid_) {
    if (info.position == pos_first_) return;   // a counter that does not move is no use (some devices report a constant 0)
    pos_valid_ = true;
    position_supported_.store(true, std::memory_order_relaxed);
    off_a_ = a;
    off_b_ = b;
    chg_a_ = chg_b_ = 0;
    return;
  }
  const int64_t da = a - off_a_, db = b - off_b_;
  if (da != 0) { ++chg_a_; off_a_ = a; }
  if (db != 0) { ++chg_b_; off_b_ = b; }
  const int64_t jump = (chg_b_ <= chg_a_) ? db : da;   // the convention that has changed less is the real one
  if (jump > 0) {
    in_gaps_.store(in_gaps_.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
    gap_frames_.store(gap_frames_.load(std::memory_order_relaxed) + static_cast<uint64_t>(jump), std::memory_order_relaxed);
    gap_ring_.push((t0 - epoch) / 1000, static_cast<uint64_t>(jump), false);
  }
}

void AudioPump::on_output(float* out, int n) {
  if (!out || n <= 0) return;
  if (reset_out_.exchange(false, std::memory_order_acq_rel)) {
    drone_.clear();
    out_callbacks_.store(0, std::memory_order_relaxed);
    out_frames_.store(0, std::memory_order_relaxed);
    out_xruns_.store(0, std::memory_order_relaxed);
  }
  if (replay_.on_output(out, n)) {
    // a replay slice (ADR 0013) instead of the drone
  } else if (drone_on_.load(std::memory_order_acquire) && ops_.drone_render) {
    const int64_t a = now();
    ops_.drone_render(ops_.ctx, out, n);
    drone_.add(now() - a);
  } else {
    std::memset(out, 0, sizeof(float) * static_cast<size_t>(n));
  }
  out_callbacks_.store(out_callbacks_.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
  out_frames_.store(out_frames_.load(std::memory_order_relaxed) + static_cast<uint64_t>(n), std::memory_order_relaxed);
}

PumpStats AudioPump::snapshot() const {
  PumpStats s;
  s.chunk = chunk_.summary();
  s.callback = callback_.summary();
  s.drone = drone_.summary();
  s.input_callbacks = in_callbacks_.load(std::memory_order_relaxed);
  s.input_frames = in_frames_.load(std::memory_order_relaxed);
  s.late_callbacks = late_.load(std::memory_order_relaxed);
  s.input_gaps = in_gaps_.load(std::memory_order_relaxed);
  s.gap_frames = gap_frames_.load(std::memory_order_relaxed);
  s.input_overruns = overruns_.load(std::memory_order_relaxed);
  s.slow_hops = slow_.load(std::memory_order_relaxed);
  s.position_supported = position_supported_.load(std::memory_order_relaxed);
  s.epoch_ns = epoch_ns_.load(std::memory_order_relaxed);
  s.output_callbacks = out_callbacks_.load(std::memory_order_relaxed);
  s.output_frames = out_frames_.load(std::memory_order_relaxed);
  s.output_xruns = out_xruns_.load(std::memory_order_relaxed);
  return s;
}

std::vector<PumpEvent> AudioPump::events(EventKind kind) const {
  std::vector<PumpEvent> out;
  const detail::EventRing& ring = kind == EventKind::LateCallback ? late_ring_ : kind == EventKind::SlowHop ? slow_ring_ : gap_ring_;
  for (const auto& it : ring.read()) {
    if (kind == EventKind::PositionGap && it.flag) continue;
    if (kind == EventKind::Overrun && !it.flag) continue;
    out.push_back(PumpEvent{kind, static_cast<double>(it.t_us) / 1e6, it.value});
  }
  return out;
}

}  // namespace intono_shim
