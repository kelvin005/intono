// ADR 0008: the note worker thread. Lifecycle (create/destroy 1000 times, clean under ASan), identical output to inline mode under random
// worker stalls (M3), overflow policy, thread accounting.
#include <gtest/gtest.h>

#include <cmath>
#include <cstdio>
#include <chrono>
#include <cstring>
#include <thread>
#include <dirent.h>
#include <vector>

#include "engine_internal.hpp"
#include "intono/intono.h"
#include "test_util.hpp"

namespace {

intono_config cfg() {
  intono_config c{};
  c.sample_rate = 48000; c.window_size = 1024; c.hop_size = 256; c.a4_hz = 440; c.tuning = 0; c.min_hz = 180; c.max_hz = 3200;
  return c;
}

int thread_count() {   // Linux: one entry per thread in /proc/self/task
  int n = 0;
  if (DIR* d = opendir("/proc/self/task")) {
    while (dirent* e = readdir(d)) if (e->d_name[0] != '.') ++n;
    closedir(d);
  }
  return n;
}

// /proc/self/task can list a joined thread for a moment while the kernel reaps it: wait up to 2 s for the count to settle at `want`.
int settled_thread_count(int want) {
  int n = thread_count();
  for (int i = 0; i < 400 && n != want; ++i) {
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
    n = thread_count();
  }
  return n;
}

// Notes, vibrato, a legato step the fit must split, gaps, noise: every tracker path.
std::vector<float> stream() {
  std::vector<float> x(24000, 0.f);
  for (auto part : {testutil::harmonic(48000, 196.0, 0.8, 0.15), testutil::harmonic(48000, 880.0, 0.4), std::vector<float>(9600, 0.f),
                    testutil::sine(48000, 523.25, 0.3), testutil::harmonic(48000, 330.0, 0.5)})
    x.insert(x.end(), part.begin(), part.end());
  std::vector<float> leg(72000);
  double ph = 0;
  for (size_t i = 0; i < leg.size(); ++i) {
    const double step = i < 36000 ? 0.0 : 80.0;
    ph += 2 * testutil::kPi * 330.0 * std::exp2((step + 30.0 * std::sin(2 * testutil::kPi * 5.5 * i / 48000.0)) / 1200) / 48000.0;
    leg[i] = static_cast<float>(0.3 * std::sin(ph));
  }
  x.insert(x.end(), leg.begin(), leg.end());
  x.insert(x.end(), 24000, 0.f);
  return x;
}

std::vector<intono_note> run(bool inline_mode, int stall_us, int chunk, const std::vector<float>& x) {
  const intono_config c = cfg();
  intono_engine* e = intono_internal::create(&c, inline_mode);
  EXPECT_NE(e, nullptr);
  if (stall_us > 0) intono_internal::set_worker_stall(e, stall_us, 777u);
  std::vector<intono_note> all;
  intono_note nb[16];
  for (size_t p = 0; p < x.size(); p += chunk) {
    intono_process(e, x.data() + p, static_cast<int>(std::min<size_t>(chunk, x.size() - p)));
    if (!inline_mode && (p / chunk) % 7 == 0) std::this_thread::yield();   // read while the worker is mid-stream
    int got;
    while ((got = intono_read_notes(e, nb, 16)) > 0) all.insert(all.end(), nb, nb + got);
  }
  intono_internal::drain(e);
  int got;
  while ((got = intono_read_notes(e, nb, 16)) > 0) all.insert(all.end(), nb, nb + got);
  EXPECT_EQ(intono_internal::dropped_records(e), 0u);
  intono_destroy(e);
  return all;
}

bool same(const std::vector<intono_note>& a, const std::vector<intono_note>& b) {
  if (a.size() != b.size()) return false;
  for (size_t i = 0; i < a.size(); ++i)
    if (std::memcmp(&a[i], &b[i], sizeof(intono_note)) != 0) return false;   // bit for bit (intono_note has no padding holes that differ: both zero-initialised)
  return true;
}

}  // namespace

// The test the user asked for: create/destroy 1000 times. Under ASan (INTONO_SANITIZE=address) this is the leak and use-after-free check.
TEST(Worker, CreateDestroyThousandTimes) {
  const intono_config c = cfg();
  const int base = thread_count();
  const std::vector<float> burst = testutil::harmonic(48000, 440.0, 0.15);
  for (int i = 0; i < 1000; ++i) {
    intono_engine* e = intono_create(&c);
    ASSERT_NE(e, nullptr) << "iteration " << i;
    if (i % 10 == 0) intono_process(e, burst.data(), static_cast<int>(burst.size()));   // destroy with records still queued
    if (i % 25 == 0) { intono_note nb[4]; intono_read_notes(e, nb, 4); }
    intono_destroy(e);
  }
  EXPECT_EQ(settled_thread_count(base), base) << "a worker thread outlived its engine";
}

TEST(Worker, OneThreadPerEngineAndJoinedOnDestroy) {
  const intono_config c = cfg();
  const int base = thread_count();
  intono_engine* a = intono_create(&c);
  intono_engine* b = intono_internal::create(&c, true);   // inline: no thread
  ASSERT_TRUE(a && b);
  EXPECT_EQ(settled_thread_count(base + 1), base + 1);
  intono_destroy(b);
  EXPECT_EQ(settled_thread_count(base + 1), base + 1);
  intono_destroy(a);
  EXPECT_EQ(settled_thread_count(base), base);
  intono_destroy(nullptr);   // still safe
}

// M3 on a synthetic stream: threaded == inline, bit for bit, whatever the worker's timing and the chunk size.
TEST(Worker, ThreadedNotesAreIdenticalToInlineUnderRandomStalls) {
  const std::vector<float> x = stream();
  const auto ref = run(true, 0, 256, x);
  ASSERT_GE(ref.size(), 4u) << "the stream must exercise the tracker";
  for (int chunk : {1, 97, 128, 256, 1000}) {
    EXPECT_TRUE(same(ref, run(false, 0, chunk, x))) << "threaded, chunk " << chunk;
    EXPECT_TRUE(same(ref, run(true, 0, chunk, x))) << "inline, chunk " << chunk;
  }
  for (int stall : {500, 3000}) EXPECT_TRUE(same(ref, run(false, stall, 256, x))) << "stall up to " << stall << " us";
}

// A full queue drops the record (never blocks); the worker ends the run at the hole and carries nothing across it.
TEST(Worker, FullQueueDropsAndEndsTheRunWithoutCrashing) {
  const intono_config c = cfg();
  intono_engine* e = intono_create(&c);
  ASSERT_NE(e, nullptr);
  intono_internal::set_worker_spin_ns(e, 20'000'000);   // the worker needs 20 ms per record: the audio thread outruns it by far
  const std::vector<float> tone = testutil::harmonic(48000, 440.0, 1.0);
  for (int rep = 0; rep < 8; ++rep) intono_process(e, tone.data(), static_cast<int>(tone.size()));   // 187 records per second of audio: 1500 > the 1024 queue
  EXPECT_GT(intono_internal::dropped_records(e), 0u);
  intono_internal::set_worker_spin_ns(e, 0);
  intono_internal::drain(e);   // the worker catches up (what was queued is processed; what was dropped is gone)
  const std::vector<float> silence(48000, 0.f);   // the silence records pushed while the queue was full were dropped too: feed it again
  intono_process(e, silence.data(), static_cast<int>(silence.size()));
  intono_internal::drain(e);
  intono_note nb[16];
  int got, n = 0;
  while ((got = intono_read_notes(e, nb, 16)) > 0) {
    for (int i = 0; i < got; ++i) {
      EXPECT_GE(nb[i].t_end, nb[i].t_start);
      EXPECT_GT(nb[i].frame_count, 0);
    }
    n += got;
  }
  EXPECT_GE(n, 1);
  intono_destroy(e);
}

// The queue stays shallow at real-time-like pacing (the soak tool measures 30 minutes; this is the quick regression).
TEST(Worker, QueueStaysShallowWhenFedInHopSizedCalls) {
  const intono_config c = cfg();
  intono_engine* e = intono_create(&c);
  ASSERT_NE(e, nullptr);
  const std::vector<float> x = stream();
  for (size_t p = 0; p + 256 <= x.size(); p += 256) {
    intono_process(e, x.data() + p, 256);
    if ((p / 256) % 16 == 0) std::this_thread::sleep_for(std::chrono::milliseconds(2));   // ~16 hops = 85 ms of audio per 2 ms: 40x real time
  }
  intono_internal::drain(e);
  EXPECT_EQ(intono_internal::dropped_records(e), 0u);
  EXPECT_LT(intono_internal::queue_high_water(e), 512u);
  intono_destroy(e);
}
