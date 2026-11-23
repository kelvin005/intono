#include "bench.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>

#include "intono/intono.h"

#ifndef INTONO_DENORMAL_GUARD
#define INTONO_DENORMAL_GUARD 1
#endif

namespace intono_shim {

namespace {
constexpr double kPi = 3.14159265358979323846;

int64_t clock_now(const Clock& c) {
  if (c.now) return c.now(c.ctx);
  return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

void append_tone(std::vector<float>& s, double hz, double seconds, int sr, float amp) {
  const size_t n = static_cast<size_t>(seconds * sr);
  const size_t fade = static_cast<size_t>(0.005 * sr);   // 5 ms in and out: no clicks between scale notes
  for (size_t i = 0; i < n; ++i) {
    float env = 1.f;
    if (i < fade) env = static_cast<float>(i) / static_cast<float>(fade);
    else if (n - i <= fade) env = static_cast<float>(n - i) / static_cast<float>(fade);
    s.push_back(amp * env * static_cast<float>(std::sin(2.0 * kPi * hz * static_cast<double>(i) / sr)));
  }
}

BenchSummary summarise(std::vector<double> ns) {
  BenchSummary r;
  if (ns.empty()) return r;
  std::sort(ns.begin(), ns.end());
  const size_t n = ns.size();
  r.median_us = ns[n / 2] / 1000.0;
  r.p99_us = ns[static_cast<size_t>(std::ceil(0.99 * static_cast<double>(n))) - 1] / 1000.0;
  r.max_us = ns.back() / 1000.0;
  return r;
}
}  // namespace

BenchSignal make_bench_signal(int sample_rate, int hop) {
  BenchSignal b;
  b.sample_rate = sample_rate;
  b.hop = hop;
  b.samples.reserve(static_cast<size_t>(13) * static_cast<size_t>(sample_rate));
  append_tone(b.samples, 440.0, 3.0, sample_rate, 0.5f);
  const double scale[] = {196.0, 220.0, 246.94, 261.63, 293.66, 329.63, 369.99, 392.0};   // G3 to G4
  for (double hz : scale) append_tone(b.samples, hz, 0.5, sample_rate, 0.5f);
  b.samples.resize(static_cast<size_t>(13) * static_cast<size_t>(sample_rate), 0.0f);   // 6 s of exact silence
  b.tone_hops = 3 * sample_rate / hop;
  b.scale_hops = 4 * sample_rate / hop;
  b.silence_hops = b.hops() - b.tone_hops - b.scale_hops;
  b.lowest_hz = 196.0;
  b.highest_hz = 440.0;
  return b;
}

BenchResult run_bench(const BenchHooks& h, int sample_rate, int hop, int runs) {
  runs = std::max(1, runs);
  const BenchSignal sig = make_bench_signal(sample_rate, hop);
  const int hops = sig.hops();
  std::vector<double> best(static_cast<size_t>(hops), 1e30);
  std::vector<double> all;
  all.reserve(static_cast<size_t>(hops) * static_cast<size_t>(runs));
  for (int r = 0; r < runs; ++r) {
    if (h.begin_run) h.begin_run(h.ctx);
    for (int i = 0; i < hops; ++i) {
      const float* in = sig.samples.data() + static_cast<size_t>(i) * static_cast<size_t>(hop);
      const int64_t a = clock_now(h.clock);
      if (h.process) h.process(h.ctx, in, hop);
      const double ns = static_cast<double>(clock_now(h.clock) - a);
      all.push_back(ns);
      best[static_cast<size_t>(i)] = std::min(best[static_cast<size_t>(i)], ns);
      if (h.after_hop) h.after_hop(h.ctx);
    }
    if (h.end_run) h.end_run(h.ctx);
  }
  BenchResult res;
  res.runs = runs;
  res.hops = hops;
  res.sample_rate = sample_rate;
  res.hop_size = hop;
  res.guard = INTONO_DENORMAL_GUARD != 0;
  res.intrinsic = summarise(best);
  res.raw = summarise(all);
  const auto seg = [&](int from, int to) { return summarise(std::vector<double>(best.begin() + from, best.begin() + to)); };
  res.intrinsic_tone = seg(0, sig.tone_hops);
  res.intrinsic_scale = seg(sig.tone_hops, sig.tone_hops + sig.scale_hops);
  res.intrinsic_silence = seg(sig.tone_hops + sig.scale_hops, hops);
  return res;
}

namespace {
struct EngineRun {
  intono_engine* e = nullptr;
  std::vector<intono_frame> frames = std::vector<intono_frame>(64);
  std::vector<intono_note> notes = std::vector<intono_note>(16);
  static void begin(void* c) {
    auto* r = static_cast<EngineRun*>(c);
    intono_config cfg{};
    cfg.sample_rate = 48000.f;
    cfg.window_size = 1024;
    cfg.hop_size = 256;
    cfg.a4_hz = 440.f;
    cfg.tuning = 0;
    cfg.min_hz = 180.f;
    cfg.max_hz = 3200.f;
    r->e = intono_create(&cfg);
  }
  static void process(void* c, const float* in, int n) {
    auto* r = static_cast<EngineRun*>(c);
    if (r->e) intono_process(r->e, in, n);
  }
  static void after(void* c) {   // what the UI thread does in the product, outside the timed call
    auto* r = static_cast<EngineRun*>(c);
    if (!r->e) return;
    intono_read_frames(r->e, r->frames.data(), static_cast<int>(r->frames.size()));
    intono_read_notes(r->e, r->notes.data(), static_cast<int>(r->notes.size()));
  }
  static void end(void* c) {
    auto* r = static_cast<EngineRun*>(c);
    if (r->e) intono_destroy(r->e);
    r->e = nullptr;
  }
};
}  // namespace

BenchResult run_bench_engine(int runs) {
  EngineRun r;
  BenchHooks h;
  h.ctx = &r;
  h.begin_run = &EngineRun::begin;
  h.process = &EngineRun::process;
  h.end_run = &EngineRun::end;
  h.after_hop = &EngineRun::after;
  return run_bench(h, 48000, 256, runs);
}

std::string BenchResult::text() const {
  char buf[640];
  std::string s;
  std::snprintf(buf, sizeof buf, "bench (guard %s): %d runs x %d hops, %d Hz, hop %d\n", guard ? "ON" : "OFF", runs, hops, sample_rate, hop_size);
  s += buf;
  std::snprintf(buf, sizeof buf, "intrinsic hop us (per-hop minimum over runs): median %.1f, p99 %.1f, max %.1f\n", intrinsic.median_us,
                intrinsic.p99_us, intrinsic.max_us);
  s += buf;
  std::snprintf(buf, sizeof buf, "  tone: median %.1f, max %.1f; scale: median %.1f, max %.1f; silence: median %.1f, max %.1f\n",
                intrinsic_tone.median_us, intrinsic_tone.max_us, intrinsic_scale.median_us, intrinsic_scale.max_us,
                intrinsic_silence.median_us, intrinsic_silence.max_us);
  s += buf;
  std::snprintf(buf, sizeof buf, "raw hop us (all runs): median %.1f, p99 %.1f, max %.1f\n", raw.median_us, raw.p99_us, raw.max_us);
  s += buf;
  return s;
}

}  // namespace intono_shim

extern "C" int intono_bench_run(int runs, char* out, int cap) {
  if (!out || cap <= 0) return 0;
  const std::string t = intono_shim::run_bench_engine(std::min(50, std::max(1, runs))).text();
  const size_t n = std::min(t.size(), static_cast<size_t>(cap - 1));
  std::memcpy(out, t.data(), n);
  out[n] = '\0';
  return static_cast<int>(n);
}
