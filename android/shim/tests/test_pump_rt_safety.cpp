// Fails if AudioPump::on_input or on_output (with the real engine behind them) allocates or takes a lock on the audio thread.
// Same instrumentation as dsp/tests/test_rt_safety.cpp (linked with --wrap, see CMakeLists.txt).
#include <gtest/gtest.h>
#include <pthread.h>

#include <atomic>
#include <cmath>
#include <cstdlib>
#include <mutex>
#include <new>
#include <vector>

#include "audio_pump.hpp"

static thread_local bool t_armed = false;
static std::atomic<long> g_allocs{0}, g_locks{0};

extern "C" {
void* __real_malloc(size_t);
void* __real_calloc(size_t, size_t);
void* __real_realloc(void*, size_t);
int __real_posix_memalign(void**, size_t, size_t);
void* __real_aligned_alloc(size_t, size_t);
int __real_pthread_mutex_lock(pthread_mutex_t*);

void* __wrap_malloc(size_t n) { if (t_armed) ++g_allocs; return __real_malloc(n); }
void* __wrap_calloc(size_t a, size_t b) { if (t_armed) ++g_allocs; return __real_calloc(a, b); }
void* __wrap_realloc(void* p, size_t n) { if (t_armed) ++g_allocs; return __real_realloc(p, n); }
int __wrap_posix_memalign(void** p, size_t a, size_t n) { if (t_armed) ++g_allocs; return __real_posix_memalign(p, a, n); }
void* __wrap_aligned_alloc(size_t a, size_t n) { if (t_armed) ++g_allocs; return __real_aligned_alloc(a, n); }
int __wrap_pthread_mutex_lock(pthread_mutex_t* m) { if (t_armed) ++g_locks; return __real_pthread_mutex_lock(m); }
}

void* operator new(size_t n) { void* p = std::malloc(n); if (!p) throw std::bad_alloc(); return p; }
void* operator new[](size_t n) { return operator new(n); }
void operator delete(void* p) noexcept { std::free(p); }
void operator delete[](void* p) noexcept { std::free(p); }
void operator delete(void* p, size_t) noexcept { std::free(p); }
void operator delete[](void* p, size_t) noexcept { std::free(p); }

namespace {
struct Armed {
  Armed() { g_allocs = 0; g_locks = 0; t_armed = true; }
  ~Armed() { t_armed = false; }
};
}  // namespace

TEST(PumpRtSafety, InstrumentationDetectsMalloc) {
  Armed a;
  void* volatile p = std::malloc(64);
  std::free(p);
  EXPECT_GE(g_allocs.load(), 1);
}

TEST(PumpRtSafety, InputAndOutputCallbacksNeitherAllocateNorLock) {
  intono_config c{};
  c.sample_rate = 48000; c.window_size = 1024; c.hop_size = 256; c.a4_hz = 440; c.tuning = 1; c.min_hz = 180; c.max_hz = 3200;
  intono_engine* e = intono_create(&c);
  ASSERT_NE(e, nullptr);
  intono_shim::PumpConfig pc;
  pc.sample_rate = 48000;
  pc.hop_size = 256;
  intono_shim::AudioPump p(intono_shim::engine_ops(e), pc);
  p.set_drone_enabled(true);
  intono_drone_set(e, 57, 0.3f, 0);
  std::vector<float> in(480), out(480);
  for (size_t i = 0; i < in.size(); ++i) in[i] = static_cast<float>(0.3 * std::sin(0.05 * static_cast<double>(i)));
  {
    Armed a;
    for (int k = 0; k < 2000; ++k) {
      p.on_input(in.data(), 480);
      p.on_output(out.data(), 480);
      if (k % 100 == 0) (void)p.snapshot();
    }
    p.request_reset();
    p.on_input(in.data(), 480);
  }
  EXPECT_EQ(g_allocs.load(), 0);
  EXPECT_EQ(g_locks.load(), 0);
  intono_destroy(e);
}

// ADR 0013: the same with the replay ring armed (recording), then frozen and playing a slice on the output thread.
TEST(PumpRtSafety, ReplayRecordingAndPlaybackNeitherAllocateNorLock) {
  intono_config c{};
  c.sample_rate = 48000;
  c.window_size = 1024;
  c.hop_size = 256;
  c.a4_hz = 440;
  c.min_hz = 180;
  c.max_hz = 3200;
  intono_engine* e = intono_create(&c);
  ASSERT_NE(e, nullptr);
  intono_shim::PumpConfig pc;
  intono_shim::AudioPump p(intono_shim::engine_ops(e), pc);
  ASSERT_TRUE(p.replay().arm(48000, 60.0));   // UI thread: allocates here, before the audio callbacks
  std::vector<float> in(480), out(480);
  for (size_t i = 0; i < in.size(); ++i) in[i] = static_cast<float>(0.3 * std::sin(0.05 * static_cast<double>(i)));
  for (int k = 0; k < 50; ++k) p.on_input(in.data(), 480);   // warm-up, unarmed instrumentation
  {
    Armed a;
    for (int k = 0; k < 2000; ++k) p.on_input(in.data(), 480);   // recording, and wrapping is not reached (20 s of 60)
    EXPECT_EQ(g_allocs.load(), 0);
    EXPECT_EQ(g_locks.load(), 0);
  }
  p.replay().freeze();
  ASSERT_TRUE(p.replay().play(p.replay().first_frame(), p.replay().end_frame()));
  {
    Armed a;
    for (int k = 0; k < 500; ++k) {
      p.on_input(in.data(), 480);    // paused: returns at once
      p.on_output(out.data(), 480);  // playback
    }
    EXPECT_EQ(g_allocs.load(), 0);
    EXPECT_EQ(g_locks.load(), 0);
  }
  p.replay().release();
  intono_destroy(e);
}

int main(int argc, char** argv) {
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
