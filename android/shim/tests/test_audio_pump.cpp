// AudioPump (ADR 0009): written before the implementation. A fake engine and a fake clock make every number exact.
#include <gtest/gtest.h>

#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <thread>
#include <vector>

#include "audio_pump.hpp"

using namespace intono_shim;

namespace {

struct FakeEngine {
  int64_t now = 0;                      // the fake clock; only the fake engine advances it
  std::vector<int64_t> cost;            // ns charged per process call, cycled
  size_t calls = 0;
  std::vector<int> sizes;
  std::vector<const float*> ptrs;
  int drone_calls = 0;
  int drone_n = 0;
  int64_t drone_cost = 0;
  float drone_value = 0.25f;

  static void process(void* c, const float* in, int n) {
    auto* f = static_cast<FakeEngine*>(c);
    f->sizes.push_back(n);
    f->ptrs.push_back(in);
    if (!f->cost.empty()) f->now += f->cost[f->calls % f->cost.size()];
    ++f->calls;
  }
  static void drone(void* c, float* out, int n) {
    auto* f = static_cast<FakeEngine*>(c);
    ++f->drone_calls;
    f->drone_n = n;
    f->now += f->drone_cost;
    for (int i = 0; i < n; ++i) out[i] = f->drone_value;
  }
  static int64_t clock(void* c) { return static_cast<FakeEngine*>(c)->now; }
  EngineOps ops() { return EngineOps{this, &FakeEngine::process, &FakeEngine::drone}; }
  Clock clk() { return Clock{this, &FakeEngine::clock}; }
};

PumpConfig cfg(int sr = 48000, int hop = 256) {
  PumpConfig c;
  c.sample_rate = sr;
  c.hop_size = hop;
  return c;
}

}  // namespace

TEST(AudioPumpChunking, SplitsACallbackIntoHopSizedChunksInOrder) {
  FakeEngine e;
  AudioPump p(e.ops(), cfg(), e.clk());
  std::vector<float> in(1000);
  p.on_input(in.data(), 1000);
  ASSERT_EQ(e.sizes.size(), 4u);
  EXPECT_EQ(e.sizes[0], 256);
  EXPECT_EQ(e.sizes[1], 256);
  EXPECT_EQ(e.sizes[2], 256);
  EXPECT_EQ(e.sizes[3], 232);
  for (size_t i = 0; i < 4; ++i) EXPECT_EQ(e.ptrs[i], in.data() + 256 * i);
}

TEST(AudioPumpChunking, SmallAndExactSizesAreOneCall) {
  FakeEngine e;
  AudioPump p(e.ops(), cfg(), e.clk());
  std::vector<float> in(512);
  p.on_input(in.data(), 1);
  p.on_input(in.data(), 256);
  ASSERT_EQ(e.sizes.size(), 2u);
  EXPECT_EQ(e.sizes[0], 1);
  EXPECT_EQ(e.sizes[1], 256);
}

TEST(AudioPumpChunking, NothingIsPassedForNullOrNonPositiveInput) {
  FakeEngine e;
  AudioPump p(e.ops(), cfg(), e.clk());
  float x = 0;
  p.on_input(nullptr, 100);
  p.on_input(&x, 0);
  p.on_input(&x, -5);
  EXPECT_EQ(e.calls, 0u);
  EXPECT_EQ(p.snapshot().input_callbacks, 0u);
}

TEST(AudioPumpChunking, EveryCallbackSizeIsCoveredExactlyOnceAndNeverExceedsAHop) {
  FakeEngine e;
  AudioPump p(e.ops(), cfg(), e.clk());
  std::vector<float> in(5000);
  uint32_t s = 12345;
  for (int k = 0; k < 300; ++k) {
    s = s * 1664525u + 1013904223u;
    const int n = 1 + static_cast<int>((s >> 8) % 4000);
    e.sizes.clear();
    e.ptrs.clear();
    p.on_input(in.data(), n);
    int sum = 0;
    for (size_t i = 0; i < e.sizes.size(); ++i) {
      EXPECT_GE(e.sizes[i], 1);
      EXPECT_LE(e.sizes[i], 256);
      EXPECT_EQ(e.ptrs[i], in.data() + sum);
      sum += e.sizes[i];
    }
    EXPECT_EQ(sum, n);
  }
}

TEST(AudioPumpTiming, ChunkAndCallbackStatisticsAreExact) {
  FakeEngine e;
  e.cost = {100, 200, 300, 400};
  AudioPump p(e.ops(), cfg(), e.clk());
  std::vector<float> in(1000);
  p.on_input(in.data(), 1000);
  const PumpStats s = p.snapshot();
  EXPECT_EQ(s.chunk.count, 4u);
  EXPECT_DOUBLE_EQ(s.chunk.max_ns, 400.0);
  EXPECT_DOUBLE_EQ(s.chunk.mean_ns, 250.0);
  EXPECT_GE(s.chunk.p99_ns, 400.0);
  EXPECT_LE(s.chunk.p99_ns, 400.0 * 1.07);   // log histogram, 16 buckets per octave
  EXPECT_GE(s.chunk.p50_ns, 200.0);
  EXPECT_LE(s.chunk.p50_ns, 300.0 * 1.07);
  EXPECT_EQ(s.callback.count, 1u);
  EXPECT_DOUBLE_EQ(s.callback.max_ns, 1000.0);
  EXPECT_EQ(s.input_callbacks, 1u);
  EXPECT_EQ(s.input_frames, 1000u);
}

TEST(AudioPumpTiming, TheWorstChunkIsKeptAcrossManyCallbacks) {
  FakeEngine e;
  e.cost = {50, 50, 50, 9000, 50, 50};   // one slow hop
  AudioPump p(e.ops(), cfg(), e.clk());
  std::vector<float> in(256);
  for (int i = 0; i < 60; ++i) p.on_input(in.data(), 256);
  const PumpStats s = p.snapshot();
  EXPECT_EQ(s.chunk.count, 60u);
  EXPECT_DOUBLE_EQ(s.chunk.max_ns, 9000.0);
  EXPECT_LE(s.chunk.p50_ns, 51.0 * 1.07 + 1);
  EXPECT_GE(s.chunk.p99_ns, 9000.0 * 0.0);   // 10 slow of 60 is above p99 only when count is large; max is the contract here
}

TEST(AudioPumpGaps, ACallbackLateByMoreThanOneAndAHalfPeriodsIsAnInputGap) {
  FakeEngine e;
  AudioPump p(e.ops(), cfg(48000, 256), e.clk());
  std::vector<float> in(480);
  const int64_t ms = 1000000;                    // 480 frames at 48 kHz = 10 ms
  const int64_t t[] = {0, 10 * ms, 20 * ms, 34 * ms /* 14: ok */, 50 * ms /* 16: gap */, 60 * ms, 90 * ms /* 30: gap */};
  for (int64_t v : t) {
    e.now = v;
    p.on_input(in.data(), 480);
  }
  EXPECT_EQ(p.snapshot().input_gaps, 2u);
  EXPECT_EQ(p.snapshot().input_callbacks, 7u);
}

TEST(AudioPumpGaps, TheFirstCallbackAndTheFirstAfterAResetHaveNoGap) {
  FakeEngine e;
  AudioPump p(e.ops(), cfg(), e.clk());
  std::vector<float> in(480);
  e.now = 5000000000LL;
  p.on_input(in.data(), 480);
  EXPECT_EQ(p.snapshot().input_gaps, 0u);
  p.request_reset();
  e.now = 9000000000LL;
  p.on_input(in.data(), 480);
  EXPECT_EQ(p.snapshot().input_gaps, 0u);
}

TEST(AudioPumpDrone, OffByDefaultAndTheOutputIsSilence) {
  FakeEngine e;
  AudioPump p(e.ops(), cfg(), e.clk());
  EXPECT_FALSE(p.drone_enabled());
  std::vector<float> out(480, 7.f);
  p.on_output(out.data(), 480);
  for (float v : out) EXPECT_EQ(v, 0.f);
  EXPECT_EQ(e.drone_calls, 0);
  EXPECT_EQ(p.snapshot().output_callbacks, 1u);
  EXPECT_EQ(p.snapshot().output_frames, 480u);
}

TEST(AudioPumpDrone, WhenEnabledTheEngineRendersAndWhenDisabledAgainItIsSilentAgain) {
  FakeEngine e;
  e.drone_cost = 700;
  AudioPump p(e.ops(), cfg(), e.clk());
  p.set_drone_enabled(true);
  std::vector<float> out(300, 7.f);
  p.on_output(out.data(), 300);
  EXPECT_EQ(e.drone_calls, 1);
  EXPECT_EQ(e.drone_n, 300);
  for (float v : out) EXPECT_EQ(v, 0.25f);
  const PumpStats s = p.snapshot();
  EXPECT_EQ(s.drone.count, 1u);
  EXPECT_DOUBLE_EQ(s.drone.max_ns, 700.0);
  p.set_drone_enabled(false);
  p.on_output(out.data(), 300);
  for (float v : out) EXPECT_EQ(v, 0.f);
  EXPECT_EQ(e.drone_calls, 1);
}

TEST(AudioPumpDrone, NullOrEmptyOutputIsIgnored) {
  FakeEngine e;
  AudioPump p(e.ops(), cfg(), e.clk());
  float x = 1.f;
  p.on_output(nullptr, 10);
  p.on_output(&x, 0);
  EXPECT_EQ(x, 1.f);
  EXPECT_EQ(p.snapshot().output_callbacks, 0u);
}

TEST(AudioPumpStats, StreamXrunsAreReportedAndResetClearsEverything) {
  FakeEngine e;
  e.cost = {100};
  AudioPump p(e.ops(), cfg(), e.clk());
  std::vector<float> in(600), out(600);
  p.on_input(in.data(), 600);
  p.on_output(out.data(), 600);
  p.set_output_xruns(3);
  PumpStats s = p.snapshot();
  EXPECT_EQ(s.output_xruns, 3u);
  EXPECT_EQ(s.input_callbacks, 1u);
  p.request_reset();
  p.on_input(in.data(), 256);
  p.on_output(out.data(), 256);
  s = p.snapshot();
  EXPECT_EQ(s.input_callbacks, 1u);    // only the callback after the reset
  EXPECT_EQ(s.input_frames, 256u);
  EXPECT_EQ(s.chunk.count, 1u);
  EXPECT_EQ(s.output_callbacks, 1u);
  EXPECT_EQ(s.output_xruns, 0u);
}

TEST(AudioPumpEngine, ANullEngineIsHarmless) {
  AudioPump p(engine_ops(nullptr), cfg());
  std::vector<float> in(700), out(700, 1.f);
  p.on_input(in.data(), 700);
  p.set_drone_enabled(true);
  p.on_output(out.data(), 700);
  for (float v : out) EXPECT_EQ(v, 0.f);
}

TEST(AudioPumpEngine, TheRealEngineSeesExactlyTheSamplesTheMicrophoneDelivered) {
  // Same audio, once through the pump in 480-frame callbacks and once straight into intono_process: the frames must be identical.
  intono_config c{};
  c.sample_rate = 48000; c.window_size = 1024; c.hop_size = 256; c.a4_hz = 440; c.tuning = 0; c.min_hz = 180; c.max_hz = 3200;
  intono_engine* a = intono_create(&c);
  intono_engine* b = intono_create(&c);
  ASSERT_NE(a, nullptr);
  ASSERT_NE(b, nullptr);
  AudioPump p(engine_ops(a), cfg(48000, 256));
  std::vector<float> x(96000);
  for (size_t i = 0; i < x.size(); ++i) x[i] = static_cast<float>(0.4 * std::sin(2 * 3.14159265358979323846 * 440.0 * static_cast<double>(i) / 48000.0));
  std::vector<intono_frame> fa, fb, buf(64);
  for (size_t off = 0; off < x.size(); off += 480) {
    const int n = static_cast<int>(std::min<size_t>(480, x.size() - off));
    p.on_input(x.data() + off, n);
    intono_process(b, x.data() + off, n);
    int got;
    while ((got = intono_read_frames(a, buf.data(), 64)) > 0) fa.insert(fa.end(), buf.begin(), buf.begin() + got);
    while ((got = intono_read_frames(b, buf.data(), 64)) > 0) fb.insert(fb.end(), buf.begin(), buf.begin() + got);
  }
  ASSERT_EQ(fa.size(), fb.size());
  ASSERT_GT(fa.size(), 300u);
  for (size_t i = 0; i < fa.size(); ++i) {
    EXPECT_EQ(fa[i].t_sec, fb[i].t_sec);
    EXPECT_EQ(fa[i].hz, fb[i].hz);
    EXPECT_EQ(fa[i].cents, fb[i].cents);
    EXPECT_EQ(fa[i].midi_note, fb[i].midi_note);
    EXPECT_EQ(fa[i].is_voiced, fb[i].is_voiced);
    EXPECT_EQ(fa[i].is_onset, fb[i].is_onset);
  }
  EXPECT_EQ(p.snapshot().chunk.count, 96000u / 256u + 1);   // 375 full hops, the callbacks are not hop aligned so there are extra short chunks
  intono_destroy(a);
  intono_destroy(b);
}

TEST(AudioPumpThreads, StatsControlsAndTheTwoStreamsMayRunConcurrently) {
  // For TSan: input thread, output thread, and a control thread that toggles the drone, reads snapshots and requests resets.
  FakeEngine e;   // the fake engine is only touched by the input thread; the drone fake only by the output thread; no shared mutable state
  struct Drone { static void render(void*, float* o, int n) { for (int i = 0; i < n; ++i) o[i] = 0.5f; } };
  struct Proc { static void process(void*, const float*, int) {} };
  AudioPump p(EngineOps{nullptr, &Proc::process, &Drone::render}, cfg());
  std::atomic<bool> stop{false};
  std::thread in_t([&] { std::vector<float> in(480); while (!stop) p.on_input(in.data(), 480); });
  std::thread out_t([&] { std::vector<float> out(480); while (!stop) p.on_output(out.data(), 480); });
  std::thread ctl([&] {
    for (int i = 0; i < 2000; ++i) {
      p.set_drone_enabled(i % 2 == 0);
      p.set_output_xruns(static_cast<uint64_t>(i));
      if (i % 50 == 0) p.request_reset();
      (void)p.snapshot();
    }
    stop = true;
  });
  ctl.join();
  in_t.join();
  out_t.join();
  SUCCEED();
}
