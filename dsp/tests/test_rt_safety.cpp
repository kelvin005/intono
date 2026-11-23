// Fails if intono_process or intono_drone_render allocates or takes a lock.
// Built with --wrap on malloc/calloc/realloc/posix_memalign/aligned_alloc/pthread_mutex_lock
// (see CMakeLists.txt); global operator new/delete are routed through the wrapped malloc.
#include <gtest/gtest.h>
#include <pthread.h>

#include <atomic>
#include <cstdlib>
#include <mutex>
#include <new>

#include "intono/intono.h"
#include "test_util.hpp"

static thread_local bool t_armed = false;   // per thread: the worker (ADR 0008) is not armed, only the thread that calls intono_process
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
intono_config cfg() {
  intono_config c{};
  c.sample_rate = 48000; c.window_size = 1024; c.hop_size = 256; c.a4_hz = 440; c.tuning = 1; c.min_hz = 180; c.max_hz = 3200;
  return c;
}
}  // namespace

// Positive controls: prove the instrumentation can actually see allocations and locks.
TEST(RtSafety, InstrumentationDetectsMallocNewAndMutex) {
  {
    Armed a;
    void* volatile p = std::malloc(64);
    std::free(p);
    EXPECT_GE(g_allocs.load(), 1);
  }
  {
    Armed a;
    int* volatile q = new int[16];
    delete[] q;
    EXPECT_GE(g_allocs.load(), 1);
  }
  {
    Armed a;
    std::mutex m;
    m.lock();
    m.unlock();
    EXPECT_GE(g_locks.load(), 1);
  }
}

static void run_rt_safety(bool inline_mode) {
  const intono_config c = cfg();
  intono_engine* e = intono_internal::create(&c, inline_mode);
  ASSERT_NE(e, nullptr);
  intono_set_tonic(e, 62);
  std::vector<intono_frame> buf(64);
  // Cover every code path: silence, noise-floor learning, voiced notes, vibrato, jumps, octave traps, onsets.
  std::vector<float> x(24000, 0.f);
  for (auto part : {testutil::harmonic(48000, 196.0, 1.0, 0.15), testutil::harmonic(48000, 880.0, 0.6), testutil::sine(48000, 2637, 0.5)})
    x.insert(x.end(), part.begin(), part.end());
  {
    std::vector<float> vib(48000);
    double ph = 0;
    for (size_t i = 0; i < vib.size(); ++i) {
      ph += 2 * testutil::kPi * 440.0 * std::exp2(30.0 * std::sin(2 * testutil::kPi * 5.5 * i / 48000.0) / 1200) / 48000.0;
      vib[i] = static_cast<float>(0.3 * std::sin(ph));
    }
    x.insert(x.end(), vib.begin(), vib.end());
  }
  {
    // a legato 80-cent step between two vibrato notes with no RMS change: only the note HMM's change-point fit splits it
    std::vector<float> leg(96000);
    double ph = 0;
    for (size_t i = 0; i < leg.size(); ++i) {
      const double step = i < 48000 ? 0.0 : 80.0;
      ph += 2 * testutil::kPi * 330.0 * std::exp2((step + 30.0 * std::sin(2 * testutil::kPi * 5.5 * i / 48000.0)) / 1200) / 48000.0;
      leg[i] = static_cast<float>(0.3 * std::sin(ph));
    }
    x.insert(x.end(), leg.begin(), leg.end());
  }
  uint32_t s = 3;
  for (int i = 0; i < 24000; ++i) x.push_back(static_cast<float>(0.2 * testutil::noise(s)));

  std::vector<float> drone(4096);
  intono_drone_set(e, 57, 0.5f, 1);
  {
    Armed a;
    for (int chunk : {1, 97, 128, 256, 4096}) {
      for (size_t p = 0; p < x.size(); p += chunk) intono_process(e, x.data() + p, static_cast<int>(std::min<size_t>(chunk, x.size() - p)));
      intono_drone_render(e, drone.data(), static_cast<int>(std::min<size_t>(chunk, drone.size())));
      intono_drone_set(e, 60, 0.4f, 0);  // parameter changes from the UI thread must not lock either
      intono_set_tonic(e, 64);
    }
  }
  EXPECT_EQ(g_allocs.load(), 0) << "audio-thread call allocated memory";
  EXPECT_EQ(g_locks.load(), 0) << "audio-thread call took a lock";
  intono_internal::drain(e);
  int n = 0, got;
  while ((got = intono_read_frames(e, buf.data(), 64)) > 0) n += got;  // frames were really produced
  EXPECT_GT(n, 100);
  intono_note nb[16];
  int nn = 0;
  while ((got = intono_read_notes(e, nb, 16)) > 0) nn += got;  // the note segmenter ran inside the armed region too
  EXPECT_GE(nn, 7) << "notes read: " << nn;   // 4 separated notes + the two halves of the legato step (the fit ran inside the armed region)
  intono_destroy(e);
}

TEST(RtSafety, ProcessAndDroneNeverAllocateOrLock) { run_rt_safety(true); }   // the certified inline path: the tracker runs on this thread too
// M4 (ADR 0008): with the worker alive, the audio thread (this one) must not allocate or lock. The worker is not armed.
TEST(RtSafety, ProcessAndDroneNeverAllocateOrLockWithWorker) { run_rt_safety(false); }

int main(int argc, char** argv) {
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
