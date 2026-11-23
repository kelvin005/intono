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

AudioPump::AudioPump(EngineOps ops, PumpConfig cfg, Clock clock) : ops_(ops), cfg_(cfg), clock_(clock) {
  if (cfg_.hop_size < 1) cfg_.hop_size = 1;
  if (cfg_.sample_rate < 1) cfg_.sample_rate = 48000;
}

int64_t AudioPump::now() const {
  if (clock_.now) return clock_.now(clock_.ctx);
  return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

void AudioPump::on_input(const float* in, int n) {
  if (!in || n <= 0) return;
  if (reset_in_.exchange(false, std::memory_order_acq_rel)) {
    chunk_.clear();
    callback_.clear();
    in_callbacks_.store(0, std::memory_order_relaxed);
    in_frames_.store(0, std::memory_order_relaxed);
    in_gaps_.store(0, std::memory_order_relaxed);
    prev_n_ = 0;
  }
  const int64_t t0 = now();
  if (prev_n_ > 0) {
    const double expected_ns = 1e9 * static_cast<double>(prev_n_) / static_cast<double>(cfg_.sample_rate);
    if (static_cast<double>(t0 - prev_start_ns_) > cfg_.gap_factor * expected_ns)
      in_gaps_.store(in_gaps_.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
  }
  prev_start_ns_ = t0;
  prev_n_ = n;

  if (ops_.process) {
    int done = 0;
    while (done < n) {
      const int m = std::min(cfg_.hop_size, n - done);
      const int64_t a = now();
      ops_.process(ops_.ctx, in + done, m);
      chunk_.add(now() - a);
      done += m;
    }
  }
  callback_.add(now() - t0);
  in_callbacks_.store(in_callbacks_.load(std::memory_order_relaxed) + 1, std::memory_order_relaxed);
  in_frames_.store(in_frames_.load(std::memory_order_relaxed) + static_cast<uint64_t>(n), std::memory_order_relaxed);
}

void AudioPump::on_output(float* out, int n) {
  if (!out || n <= 0) return;
  if (reset_out_.exchange(false, std::memory_order_acq_rel)) {
    drone_.clear();
    out_callbacks_.store(0, std::memory_order_relaxed);
    out_frames_.store(0, std::memory_order_relaxed);
    out_xruns_.store(0, std::memory_order_relaxed);
  }
  if (drone_on_.load(std::memory_order_acquire) && ops_.drone_render) {
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
  s.input_gaps = in_gaps_.load(std::memory_order_relaxed);
  s.output_callbacks = out_callbacks_.load(std::memory_order_relaxed);
  s.output_frames = out_frames_.load(std::memory_order_relaxed);
  s.output_xruns = out_xruns_.load(std::memory_order_relaxed);
  return s;
}

}  // namespace intono_shim
