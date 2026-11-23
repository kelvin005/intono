// AudioPump (ADR 0009): everything the audio callbacks do between the audio stream and libintono, with no Android dependency.
//
//   on_input(in, n)   input (microphone) callback: hands the samples to intono_process in chunks of at most one hop, so a chunk
//                     completes at most one hop and its wall time is that hop's cost. Records timing, input-gap and slow-hop statistics.
//
// Input gaps (ADR 0009 Note 2, after the 2026-11-23 device run): a gap is a discontinuity of the stream's frame position, not a late
// callback. Late callbacks by the wall clock are counted separately: in shared mode they are bursts, not lost audio.
//   on_output(out, n) output callback: silence while the drone is off (the default), intono_drone_render while it is on.
//
// Real-time rules: no allocation, no lock, no syscall in on_input / on_output (a clock read is a vDSO call). Statistics are written by
// one thread per side with relaxed atomics and read by any thread through snapshot(). Resets are requested from any thread and applied
// by the audio thread at the start of its next callback, so the audio thread is the only writer.
#pragma once
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <vector>

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
  double gap_factor = 1.5;     // an input callback later than gap_factor expected periods counts as late (not as a gap)
  int64_t slow_hop_ns = 1000000;   // a chunk slower than this (exclusive) is logged with its time
};

// What the stream knows about itself at a callback; -1 means unavailable.
struct InputInfo {
  int64_t position = -1;   // the stream's frames-read counter as sampled in the callback (see PumpStats::position_supported)
  int64_t xruns = -1;      // the stream's overrun count
};

enum class EventKind : uint8_t { LateCallback, PositionGap, Overrun, SlowHop };

// value: LateCallback and SlowHop in microseconds, PositionGap in frames, Overrun in overruns since the previous reading.
// t_s: seconds since PumpStats::epoch_ns.
struct PumpEvent {
  EventKind kind = EventKind::SlowHop;
  double t_s = 0;
  uint64_t value = 0;
};

struct TimingSummary {
  uint64_t count = 0;
  double mean_ns = 0, max_ns = 0, p50_ns = 0, p99_ns = 0;   // percentiles: upper bound of a log bucket, 16 per octave (<= 6.3% above)
};

struct PumpStats {
  TimingSummary chunk;       // one intono_process call (at most one hop)
  TimingSummary callback;    // a whole input callback
  TimingSummary drone;       // one intono_drone_render call
  uint64_t input_callbacks = 0, input_frames = 0;
  uint64_t late_callbacks = 0;       // by the wall clock, later than gap_factor expected periods
  uint64_t input_gaps = 0;           // strict: stream position discontinuities
  uint64_t gap_frames = 0;           // frames lost in those gaps
  uint64_t input_overruns = 0;       // the stream's own overrun count, since the first reading
  uint64_t slow_hops = 0;            // chunks slower than PumpConfig::slow_hop_ns
  bool position_supported = false;   // the position counter advanced; false means gaps cannot be measured on this device
  int64_t epoch_ns = 0;              // the clock value at construction or at the last reset: event times count from it
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

// The newest 32 events, each packed into one word (40 bits of microseconds since the epoch, 1 flag bit, 23 bits of value) so a reader on
// another thread never sees a torn event. One writer thread; a reader racing the writer may see an event newer than the one it counted.
class EventRing {
 public:
  static constexpr int kCap = 32;
  void push(int64_t t_us, uint64_t value, bool flag = false);
  void clear() { count_.store(0, std::memory_order_relaxed); }
  struct Item { int64_t t_us; uint64_t value; bool flag; };
  std::vector<Item> read() const;   // oldest first

 private:
  std::atomic<uint64_t> slots_[kCap] = {};
  std::atomic<uint64_t> count_{0};
};
}  // namespace detail

class AudioPump {
 public:
  AudioPump(EngineOps ops, PumpConfig cfg, Clock clock = {});

  // Audio threads (one input thread, one output thread; they may differ).
  void on_input(const float* in, int n, InputInfo info = {});
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
  std::vector<PumpEvent> events(EventKind kind) const;   // the newest 32 of that kind, oldest first (allocates: not for audio threads)

 private:
  void note_position(const InputInfo& info, int n, int64_t t0);
  int64_t now() const;

  EngineOps ops_;
  PumpConfig cfg_;
  Clock clock_;

  std::atomic<bool> drone_on_{false}, reset_in_{false}, reset_out_{false};
  std::atomic<uint64_t> out_xruns_{0};

  // input side (input thread writes)
  detail::Timing chunk_, callback_;
  std::atomic<uint64_t> in_callbacks_{0}, in_frames_{0}, late_{0}, in_gaps_{0}, gap_frames_{0}, overruns_{0}, slow_{0};
  std::atomic<bool> position_supported_{false};
  std::atomic<int64_t> epoch_ns_{0};
  detail::EventRing late_ring_, gap_ring_, slow_ring_;   // gap_ring_: flag false = position gap, true = overrun
  int64_t prev_start_ns_ = 0;
  int prev_n_ = 0;   // 0: no previous callback (first, or first after a reset)
  // position tracking (input thread). Two conventions for the counter are tracked, because whether it already includes the callback's
  // own frames is not documented: A = frames read before the callback, B = including it. The convention whose offset (position minus
  // frames passed to the pump) changes less is the real one; a gap is a change of its offset.
  bool pos_seen_ = false, pos_valid_ = false;
  int64_t pos_first_ = 0, off_a_ = 0, off_b_ = 0;
  uint32_t chg_a_ = 0, chg_b_ = 0;
  bool xr_seen_ = false;
  int64_t xr_prev_ = 0, xr_base_ = 0;

  // output side (output thread writes)
  detail::Timing drone_;
  std::atomic<uint64_t> out_callbacks_{0}, out_frames_{0};
};

}  // namespace intono_shim
