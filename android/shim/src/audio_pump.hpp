// AudioPump (ADR 0009): everything the audio callbacks do between the audio stream and libintono, with no Android dependency.
//
//   on_input(in, n)   input (microphone) callback: hands the samples to intono_process in chunks of at most one hop, so a chunk
//                     completes at most one hop and its wall time is that hop's cost. Records timing and input-gap statistics.
//   on_output(out, n) output callback: silence while the drone is off (the default), intono_drone_render while it is on.
//
// Real-time rules: no allocation, no lock, no syscall in on_input / on_output (a clock read is a vDSO call). Statistics are written by
// one thread per side with relaxed atomics and read by any thread through snapshot(). Resets are requested from any thread and applied
// by the audio thread at the start of its next callback, so the audio thread is the only writer.
#pragma once
#include <atomic>
#include <cstddef>
#include <cstdint>

#include "intono/intono.h"

namespace intono_shim {

// What the pump calls. Real engines use engine_ops(); the tests use fakes.
struct EngineOps {
  void* ctx = nullptr;
  void (*process)(void* ctx, const float* in, int n) = nullptr;
  void (*drone_render)(void* ctx, float* out, int n) = nullptr;
};
EngineOps engine_ops(intono_engine* e);   // null engine: both calls are no-ops

// Monotonic nanoseconds. Default (now == nullptr): std::chrono::steady_clock.
struct Clock {
  void* ctx = nullptr;
  int64_t (*now)(void* ctx) = nullptr;
};

struct PumpConfig {
  int sample_rate = 48000;
  int hop_size = 256;          // chunk size limit for intono_process
  double gap_factor = 1.5;     // an input callback later than gap_factor expected periods counts as a gap
};

struct TimingSummary {
  uint64_t count = 0;
  double mean_ns = 0, max_ns = 0, p50_ns = 0, p99_ns = 0;   // percentiles: upper bound of a log bucket, 16 per octave (<= 6.3% above)
};

struct PumpStats {
  TimingSummary chunk;       // one intono_process call (at most one hop)
  TimingSummary callback;    // a whole input callback
  TimingSummary drone;       // one intono_drone_render call
  uint64_t input_callbacks = 0, input_frames = 0, input_gaps = 0;
  uint64_t output_callbacks = 0, output_frames = 0, output_xruns = 0;
};

namespace detail {
// Single-writer statistics accumulator over a fixed log histogram. add() is audio-thread only.
class Timing {
 public:
  static constexpr int kBuckets = 640;
  void add(int64_t ns);
  void clear();
  TimingSummary summary() const;

 private:
  std::atomic<uint64_t> count_{0}, sum_{0}, max_{0};
  std::atomic<uint32_t> hist_[kBuckets] = {};
};
}  // namespace detail

class AudioPump {
 public:
  AudioPump(EngineOps ops, PumpConfig cfg, Clock clock = {});

  // Audio threads (one input thread, one output thread; they may differ).
  void on_input(const float* in, int n);
  void on_output(float* out, int n);

  // Any thread.
  void set_drone_enabled(bool on) { drone_on_.store(on, std::memory_order_release); }
  bool drone_enabled() const { return drone_on_.load(std::memory_order_acquire); }
  void set_output_xruns(uint64_t n) { out_xruns_.store(n, std::memory_order_relaxed); }
  void request_reset() {
    reset_in_.store(true, std::memory_order_release);
    reset_out_.store(true, std::memory_order_release);
  }
  PumpStats snapshot() const;

 private:
  int64_t now() const;

  EngineOps ops_;
  PumpConfig cfg_;
  Clock clock_;

  std::atomic<bool> drone_on_{false}, reset_in_{false}, reset_out_{false};
  std::atomic<uint64_t> out_xruns_{0};

  // input side (input thread writes)
  detail::Timing chunk_, callback_;
  std::atomic<uint64_t> in_callbacks_{0}, in_frames_{0}, in_gaps_{0};
  int64_t prev_start_ns_ = 0;
  int prev_n_ = 0;   // 0: no previous callback (first, or first after a reset)

  // output side (output thread writes)
  detail::Timing drone_;
  std::atomic<uint64_t> out_callbacks_{0}, out_frames_{0};
};

}  // namespace intono_shim
