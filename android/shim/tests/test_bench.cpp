// Bench core (ADR 0009 decision 5): written before the implementation. A fake process hook with exact per-hop costs and a fake clock make
// every number exact; one test runs the real engine on the host.
#include <gtest/gtest.h>

#include <cmath>
#include <cstring>
#include <string>
#include <vector>

#include "bench.hpp"

using namespace intono_shim;

namespace {
struct FakeRun {
  int64_t now = 0;
  int run = -1;
  int hop = 0;
  // cost(run, hop) in ns
  int64_t (*cost)(int run, int hop) = nullptr;
  static void begin(void* c) { auto* f = static_cast<FakeRun*>(c); ++f->run; f->hop = 0; }
  static void process(void* c, const float*, int) {
    auto* f = static_cast<FakeRun*>(c);
    f->now += f->cost(f->run, f->hop++);
  }
  static void end(void*) {}
  static int64_t clock(void* c) { return static_cast<FakeRun*>(c)->now; }
  BenchHooks hooks() { return BenchHooks{this, &begin, &process, &end, Clock{this, &clock}}; }
};
}  // namespace

TEST(BenchSignal, IsGeneratedDeterministicAndEndsInExactSilence) {
  const BenchSignal a = make_bench_signal(48000, 256), b = make_bench_signal(48000, 256);
  EXPECT_EQ(a.samples.size(), 13u * 48000u);
  EXPECT_EQ(a.samples, b.samples);
  EXPECT_EQ(a.hops(), 2437);   // 624000 / 256, rounded down
  float peak = 0;
  for (float v : a.samples) peak = std::max(peak, std::fabs(v));
  EXPECT_GT(peak, 0.3f);
  EXPECT_LE(peak, 0.5f);
  for (size_t i = a.samples.size() - 6 * 48000; i < a.samples.size(); ++i) ASSERT_EQ(a.samples[i], 0.0f) << i;   // 6 s of digital silence
  EXPECT_EQ(a.tone_hops, 3 * 48000 / 256);
  EXPECT_EQ(a.scale_hops, 4 * 48000 / 256);
  EXPECT_EQ(a.tone_hops + a.scale_hops + a.silence_hops, a.hops());
}

TEST(BenchSignal, UsesOnlyFrequenciesInsideTheEnginesSearchRange) {
  // 440 Hz tone then a G3..G4 scale: nothing below the 180 Hz floor, so every segment is a case the engine is meant to track.
  const BenchSignal s = make_bench_signal(48000, 256);
  EXPECT_GE(s.lowest_hz, 180.0);
  EXPECT_LE(s.highest_hz, 3200.0);
}

TEST(BenchRun, IntrinsicIsThePerHopMinimumOverRunsAndRawKeepsTheSpike) {
  FakeRun f;
  f.cost = [](int run, int hop) -> int64_t { return 1000 + 10 * (hop % 5) + ((run == 3 && hop == 100) ? 90000 : 0); };
  const BenchResult r = run_bench(f.hooks(), 48000, 256, 10);
  EXPECT_EQ(r.runs, 10);
  EXPECT_EQ(r.hops, 2437);
  EXPECT_NEAR(r.intrinsic.max_us, 1.04, 1e-9);   // the one-run spike is not intrinsic
  EXPECT_NEAR(r.raw.max_us, 91.0, 1e-9);         // but it is the raw worst
  EXPECT_NEAR(r.intrinsic.median_us, 1.02, 1e-9);
  EXPECT_NEAR(r.raw.median_us, 1.02, 1e-9);
}

TEST(BenchRun, AHopSlowInEveryRunIsIntrinsic) {
  FakeRun f;
  f.cost = [](int, int hop) -> int64_t { return hop == 100 ? 250000 : 2000; };
  const BenchResult r = run_bench(f.hooks(), 48000, 256, 10);
  EXPECT_NEAR(r.intrinsic.max_us, 250.0, 1e-9);
  EXPECT_NEAR(r.intrinsic.median_us, 2.0, 1e-9);
}

TEST(BenchRun, SegmentsAreSummarisedSeparately) {
  FakeRun f;
  const BenchSignal sig = make_bench_signal(48000, 256);
  const int silence_from = sig.tone_hops + sig.scale_hops;
  static int s_silence_from;
  s_silence_from = silence_from;
  f.cost = [](int, int hop) -> int64_t { return hop >= s_silence_from ? 130000 : 14000; };   // the denormal case: slow in the silent tail
  const BenchResult r = run_bench(f.hooks(), 48000, 256, 10);
  EXPECT_NEAR(r.intrinsic_tone.max_us, 14.0, 1e-9);
  EXPECT_NEAR(r.intrinsic_scale.max_us, 14.0, 1e-9);
  EXPECT_NEAR(r.intrinsic_silence.max_us, 130.0, 1e-9);
  EXPECT_NEAR(r.intrinsic.max_us, 130.0, 1e-9);
}

TEST(BenchRun, P99IsTheNearestRankAndRunsAreClamped) {
  FakeRun f;
  f.cost = [](int, int hop) -> int64_t { return 1000 + hop; };   // strictly increasing: sorted order is hop order
  const BenchResult r = run_bench(f.hooks(), 48000, 256, 0);     // 0 runs becomes 1
  EXPECT_EQ(r.runs, 1);
  const int n = r.hops;
  EXPECT_NEAR(r.intrinsic.p99_us, (1000 + (static_cast<int>(std::ceil(0.99 * n)) - 1)) / 1000.0, 1e-9);
  EXPECT_NEAR(r.intrinsic.max_us, (1000 + n - 1) / 1000.0, 1e-9);
}

TEST(BenchText, NamesTheGuardTheShapeAndTheNumbers) {
  FakeRun f;
  f.cost = [](int, int) -> int64_t { return 20000; };
  BenchResult r = run_bench(f.hooks(), 48000, 256, 10);
  const std::string t = r.text();
  EXPECT_NE(t.find("guard ON"), std::string::npos) << t;   // the default build
  EXPECT_NE(t.find("10 runs x 2437 hops"), std::string::npos) << t;
  EXPECT_NE(t.find("48000 Hz"), std::string::npos) << t;
  EXPECT_NE(t.find("intrinsic"), std::string::npos) << t;
  EXPECT_NE(t.find("silence"), std::string::npos) << t;
  EXPECT_NE(t.find("20.0"), std::string::npos) << t;
  r.guard = false;
  EXPECT_NE(r.text().find("guard OFF"), std::string::npos);
}

TEST(BenchEngine, TheRealEngineRunsTheWholeSignalOnTheHost) {
  const BenchResult r = run_bench_engine(3);
  EXPECT_EQ(r.runs, 3);
  EXPECT_EQ(r.hops, 2437);
  EXPECT_GT(r.intrinsic.median_us, 0.0);
  EXPECT_LT(r.intrinsic.median_us, 5000.0);   // a hop is 5333 us of audio; a host core is far faster than that
  EXPECT_GE(r.raw.max_us, r.intrinsic.max_us);
}

TEST(BenchC, WritesTheReportIntoTheCallersBufferWithoutOverrunning) {
  char buf[8192];
  std::memset(buf, 'x', sizeof buf);
  const int n = intono_bench_run(2, buf, sizeof buf);
  ASSERT_GT(n, 50);
  ASSERT_LT(n, static_cast<int>(sizeof buf));
  EXPECT_EQ(buf[n], '\0');
  EXPECT_NE(std::string(buf).find("2 runs x 2437 hops"), std::string::npos);

  char small[16];
  std::memset(small, 'x', sizeof small);
  const int m = intono_bench_run(1, small, sizeof small);
  EXPECT_EQ(m, static_cast<int>(sizeof small) - 1);   // truncated, always terminated
  EXPECT_EQ(small[sizeof small - 1], '\0');
  EXPECT_EQ(intono_bench_run(1, nullptr, 0), 0);
}
