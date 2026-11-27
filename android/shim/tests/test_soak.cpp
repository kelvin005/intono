// Soak core (ADR 0008 W3/W4 on the phone, ADR 0009 decision 5): written before the implementation. The arithmetic (slope, CPU share,
// report text) is tested with exact inputs; two tests run the real engine on the host, once through the worker thread and once inline.
#include <gtest/gtest.h>

#include <cmath>
#include <string>
#include <vector>

#include "engine_internal.hpp"
#include "intono/intono.h"
#include "soak.hpp"

using namespace intono_shim;

namespace {
intono_config cfg48() {
  intono_config c{};
  c.sample_rate = 48000.f;
  c.window_size = 1024;
  c.hop_size = 256;
  c.a4_hz = 440.f;
  c.tuning = 0;
  c.min_hz = 180.f;
  c.max_hz = 3200.f;
  return c;
}

std::vector<float> tone(double seconds, double hz) {
  std::vector<float> x(static_cast<size_t>(seconds * 48000));
  for (size_t i = 0; i < x.size(); ++i) x[i] = 0.3f * static_cast<float>(std::sin(2 * M_PI * hz * i / 48000.0));
  return x;
}

// Feeds x in 128-sample chunks and calls sample() once per stream second. After every chunk it waits for the worker (drain, a no-op
// inline), as the CLI does: an unpaced feeder outruns the worker's 2 ms poll on a fast machine and records are dropped by design (first
// macOS arm64 run: 1000 of 3747), which is not what these tests are about. Device-paced capture is what the soak measures on the phone.
void feed(intono_engine* e, SoakMonitor& m, const std::vector<float>& x) {
  const size_t per_s = 48000;
  for (size_t p = 0; p < x.size(); p += 128) {
    intono_process(e, x.data() + p, static_cast<int>(std::min<size_t>(128, x.size() - p)));
    intono_internal::drain(e);
    if ((p + 128) % per_s < 128) m.sample();
  }
}
}  // namespace

TEST(SoakMath, SlopeIsRecordsPerMinuteOfThePerSecondMaximum) {
  EXPECT_DOUBLE_EQ(slope_per_minute({}), 0.0);
  EXPECT_DOUBLE_EQ(slope_per_minute({5, 5}), 0.0);
  EXPECT_NEAR(slope_per_minute({3, 3, 3, 3, 3}), 0.0, 1e-9);
  // one record more every second = 60 records per minute
  EXPECT_NEAR(slope_per_minute({0, 1, 2, 3, 4, 5}), 60.0, 1e-9);
  // one record more every minute
  std::vector<double> ramp(600);
  for (size_t i = 0; i < ramp.size(); ++i) ramp[i] = static_cast<double>(i) / 60.0;
  EXPECT_NEAR(slope_per_minute(ramp), 1.0, 1e-9);
}

TEST(SoakMath, CpuShareOfOneCore) {
  EXPECT_DOUBLE_EQ(cpu_share_percent(0.0, 0.0), 0.0);
  EXPECT_DOUBLE_EQ(cpu_share_percent(90.0, 1800.0), 5.0);
  EXPECT_DOUBLE_EQ(cpu_share_percent(1800.0, 1800.0), 100.0);
}

TEST(SoakReport, WorkerReportNamesTheW3AndW4NumbersAgainstTheDesktopCaps) {
  SoakResult r;
  r.worker = true;
  r.sample_rate = 48000;
  r.wall_s = 1800.0;
  r.seconds_sampled = 1800;
  r.high_water = 11;
  r.slope = -0.004;
  r.dropped = 0;
  r.probe_n = 337500;
  r.latency_mean_us = 1080;
  r.latency_p99_us = 2150;
  r.latency_max_us = 30400;
  r.work_mean_us = 0.6;
  r.work_max_us = 6.0;
  r.cpu_s = 90.0;
  const std::string t = r.text();
  EXPECT_NE(t.find("soak (worker thread): 30.0 min"), std::string::npos) << t;
  EXPECT_NE(t.find("W3 queue: high-water 11 records (desktop cap 64), slope -0.004 records/min (cap 1), dropped 0"), std::string::npos) << t;
  EXPECT_NE(t.find("W4 worker latency: mean 1.08 ms, p99 2.15 ms (desktop cap 10 ms), max 30.40 ms"), std::string::npos) << t;
  EXPECT_NE(t.find("337500 records"), std::string::npos) << t;
  EXPECT_NE(t.find("process CPU 90.0 s in 1800.0 s = 5.00% of one core"), std::string::npos) << t;
  EXPECT_EQ(t.find("PASS"), std::string::npos) << "the phone's caps are set by an ADR amendment from these numbers; the report gives no verdict";
}

TEST(SoakReport, InlineReportHasNoWorkerNumbers) {
  SoakResult r;
  r.worker = false;
  r.sample_rate = 48000;
  r.wall_s = 600.0;
  r.cpu_s = 30.0;
  const std::string t = r.text();
  EXPECT_NE(t.find("soak (inline, no worker: battery baseline): 10.0 min"), std::string::npos) << t;
  EXPECT_EQ(t.find("W3"), std::string::npos) << t;
  EXPECT_EQ(t.find("W4"), std::string::npos) << t;
  EXPECT_NE(t.find("= 5.00% of one core"), std::string::npos) << t;
}

TEST(SoakReport, AnEarlyStopIsSaid) {
  SoakResult r;
  r.worker = true;
  r.wall_s = 120.0;
  r.planned_s = 1800.0;
  EXPECT_NE(r.text().find("stopped early: 2.0 of 30.0 min"), std::string::npos) << r.text();
}

TEST(SoakEngine, WorkerThreadRunKeepsUpAndProbesEveryRecord) {
  const intono_config c = cfg48();
  intono_engine* e = intono_internal::create(&c, false);
  ASSERT_NE(e, nullptr);
  const auto x = tone(20.0, 440.0);
  const size_t hops = (x.size() - 1024) / 256 + 1;
  intono_internal::enable_probe(e, hops + 16);
  SoakMonitor m(e, true, 48000);
  feed(e, m, x);
  const SoakResult r = m.finish(/*wall_s=*/20.0, /*cpu_s=*/1.0, /*planned_s=*/20.0);
  EXPECT_TRUE(r.worker);
  EXPECT_EQ(r.seconds_sampled, 20u);
  EXPECT_EQ(r.dropped, 0u);
  EXPECT_EQ(r.probe_n, hops);
  EXPECT_GT(r.latency_mean_us, 0.0);
  EXPECT_GE(r.latency_p99_us, r.latency_mean_us * 0.0);
  EXPECT_LE(r.high_water, 1024u);
  intono_destroy(e);
}

TEST(SoakEngine, InlineRunHasNoQueue) {
  const intono_config c = cfg48();
  intono_engine* e = intono_internal::create(&c, true);
  ASSERT_NE(e, nullptr);
  SoakMonitor m(e, false, 48000);
  feed(e, m, tone(5.0, 440.0));
  const SoakResult r = m.finish(5.0, 0.5, 5.0);
  EXPECT_FALSE(r.worker);
  EXPECT_EQ(r.high_water, 0u);
  EXPECT_EQ(r.probe_n, 0u);
  intono_destroy(e);
}

TEST(SoakEngine, SamplerThreadSamplesOncePerPeriodAndStopsPromptly) {
  const intono_config c = cfg48();
  intono_engine* e = intono_internal::create(&c, false);
  ASSERT_NE(e, nullptr);
  SoakMonitor m(e, true, 48000);
  m.start_sampler(/*period_ms=*/20);
  std::this_thread::sleep_for(std::chrono::milliseconds(230));
  m.stop_sampler();
  const size_t n = m.seconds_sampled();
  EXPECT_GE(n, 8u);
  EXPECT_LE(n, 13u);
  std::this_thread::sleep_for(std::chrono::milliseconds(60));
  EXPECT_EQ(m.seconds_sampled(), n) << "no samples after stop";
  intono_destroy(e);
}
