// Soak core (ADR 0008 W3/W4 measured on the phone; ADR 0009 decision 5): the product path (microphone, AudioPump, engine) runs for a
// long time while a sampler thread reads, once a second, the note worker's queue high-water mark since the previous reading (and resets
// it). At the end: the overall high-water, the least-squares slope of the per-second maxima (records per minute), dropped records, the
// worker latency probe (push on the audio thread to tracker done, mean / p99 / max) and the process CPU share. Timings only, never audio.
//
// A run in inline mode (no worker thread) is the battery baseline: the same capture and UI, without the 2 ms poll, so the poll's power
// cost is the difference between the two runs (ADR 0008 "polling power cost"). The report states numbers, not verdicts: the phone's caps
// are set by an ADR amendment from them. Portable C++ (no Android headers), tested on the host.
#pragma once
#include <atomic>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "intono/intono.h"

namespace intono_shim {

// Least-squares slope of y[i] (one value per second) in units per minute. 0 for fewer than 2 points.
double slope_per_minute(const std::vector<double>& y);
// CPU seconds as a percentage of one core over the wall time. 0 if wall_s is 0.
double cpu_share_percent(double cpu_s, double wall_s);

struct SoakResult {
  bool worker = true;
  int sample_rate = 0;
  double wall_s = 0, planned_s = 0, cpu_s = 0;
  size_t seconds_sampled = 0, high_water = 0;
  double slope = 0;
  uint64_t dropped = 0;
  size_t probe_n = 0;
  double latency_mean_us = 0, latency_p99_us = 0, latency_max_us = 0, work_mean_us = 0, work_max_us = 0;
  std::string text() const;
};

class SoakMonitor {
 public:
  // e: the engine (threaded or inline); for the latency numbers the caller arms the probe (intono_internal::enable_probe) before the
  // first intono_process. worker: whether e was created with the worker thread.
  SoakMonitor(intono_engine* e, bool worker, int sample_rate);
  ~SoakMonitor();

  // One reading: the queue high-water since the previous reading, then reset. Any non-audio thread; no-op for an inline engine.
  void sample();
  // A thread that calls sample() every period_ms until stop_sampler().
  void start_sampler(int period_ms = 1000);
  void stop_sampler();
  size_t seconds_sampled() const;
  // Live progress line for the UI (elapsed readings, high-water so far, drops so far).
  std::string status() const;

  // After capture has stopped (no more intono_process): stops the sampler, reads the probe (which drains the worker) and returns the
  // numbers. wall_s and cpu_s are measured by the caller over the run; planned_s is the requested length (an early stop is reported).
  SoakResult finish(double wall_s, double cpu_s, double planned_s);

 private:
  intono_engine* e_;
  bool worker_;
  int sample_rate_;
  mutable std::mutex mu_;
  std::vector<double> per_second_max_;
  size_t high_water_ = 0;
  std::atomic<bool> stop_{false};
  std::thread sampler_;
};

// Process CPU time in seconds (CLOCK_PROCESS_CPUTIME_ID) and a monotonic wall clock in seconds, for the caller's measurements.
double process_cpu_seconds();
double monotonic_seconds();

}  // namespace intono_shim
