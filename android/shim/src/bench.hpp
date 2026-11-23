// Bench core (ADR 0009 decision 5): the worst-hop measurement ADR 0008 asks for, on a generated signal so runs are repeatable.
// Timings only, never audio; no recording is bundled. The signal is 3 s of a 440 Hz tone, a 4 s scale of eight half-second notes and
// 6 s of digital silence (the denormal case). Per hop the cost of one intono_process call is measured; "intrinsic" is the per-hop minimum
// over the runs (ADR 0008's method: what the hop costs when the OS does not interfere), "raw" is every sample of every run.
//
// run_bench is generic over hooks so the arithmetic is tested with a fake clock; run_bench_engine uses the real engine.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

#include "audio_pump.hpp"   // Clock

namespace intono_shim {

struct BenchSignal {
  std::vector<float> samples;
  int sample_rate = 48000;
  int hop = 256;
  int tone_hops = 0, scale_hops = 0, silence_hops = 0;
  double lowest_hz = 0, highest_hz = 0;
  int hops() const { return static_cast<int>(samples.size()) / hop; }
};
BenchSignal make_bench_signal(int sample_rate, int hop);

struct BenchHooks {
  void* ctx = nullptr;
  void (*begin_run)(void* ctx) = nullptr;
  void (*process)(void* ctx, const float* in, int n) = nullptr;   // the timed call
  void (*end_run)(void* ctx) = nullptr;
  Clock clock;
  void (*after_hop)(void* ctx) = nullptr;                         // untimed (the UI thread's reads in the product)
};

struct BenchSummary {
  double median_us = 0, p99_us = 0, max_us = 0;
};

struct BenchResult {
  int runs = 0, hops = 0, sample_rate = 0, hop_size = 0;
  bool guard = true;   // whether this build has the denormal guard (INTONO_DENORMAL_GUARD)
  BenchSummary intrinsic, raw;
  BenchSummary intrinsic_tone, intrinsic_scale, intrinsic_silence;
  std::string text() const;
};

BenchResult run_bench(const BenchHooks& hooks, int sample_rate, int hop, int runs);
BenchResult run_bench_engine(int runs);   // libintono at 48 kHz, window 1024, hop 256 (the app's configuration)

}  // namespace intono_shim

// For dart:ffi: the report as text in the caller's buffer (always terminated; truncated if it does not fit). Returns its length.
extern "C" int intono_bench_run(int runs, char* out, int cap);
