// ReplayRing (ADR 0013): the last 60 s of a scale run in RAM, replayed after the run, zeroed and released. Written before the ring.
#include <gtest/gtest.h>

#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <string>
#include <thread>
#ifdef __linux__
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#endif
#include <vector>

#include "audio_pump.hpp"
#include "replay_ring.hpp"

using intono_shim::AudioPump;
using intono_shim::EngineOps;
using intono_shim::PumpConfig;
using intono_shim::ReplayRing;

namespace {

// An allocator that records what the ring hands back: whether every sample was zero at release, and how often it was called.
struct Spy {
  int allocs = 0, releases = 0;
  bool zero_at_release = true;
  size_t last_n = 0;
  static float* alloc(void* c, size_t n) {
    auto* s = static_cast<Spy*>(c);
    ++s->allocs;
    s->last_n = n;
    return static_cast<float*>(std::calloc(n, sizeof(float)));
  }
  static void release(void* c, float* p, size_t n) {
    auto* s = static_cast<Spy*>(c);
    ++s->releases;
    for (size_t i = 0; i < n; ++i)
      if (p[i] != 0.f) s->zero_at_release = false;
    std::free(p);
  }
  ReplayRing::Allocator a() { return ReplayRing::Allocator{this, &Spy::alloc, &Spy::release}; }
};

// Writes the ramp v(f) = f (the absolute frame number) in uneven blocks.
void ramp(ReplayRing& r, int64_t& f, int64_t frames, int block = 37) {
  std::vector<float> b(static_cast<size_t>(block));
  for (int64_t done = 0; done < frames;) {
    const int m = static_cast<int>(std::min<int64_t>(block, frames - done));
    for (int i = 0; i < m; ++i) b[static_cast<size_t>(i)] = static_cast<float>(f + i);
    r.on_input(b.data(), m);
    f += m;
    done += m;
  }
}

std::vector<float> drain(ReplayRing& r, int block = 64) {
  std::vector<float> all, b(static_cast<size_t>(block));
  for (int guard = 0; guard < 100000 && r.playing(); ++guard) {
    std::fill(b.begin(), b.end(), -1.f);
    if (!r.on_output(b.data(), block)) break;
    all.insert(all.end(), b.begin(), b.end());
  }
  return all;
}

}  // namespace

TEST(ReplayRing, KeepsExactlyTheLastSecondsAndWraps) {
  Spy spy;
  ReplayRing r(spy.a());
  ASSERT_TRUE(r.arm(1000, 2.0));   // 2000 frames
  EXPECT_EQ(spy.last_n, 2000u);
  int64_t f = 0;
  ramp(r, f, 5000);
  r.freeze();
  EXPECT_EQ(r.end_frame(), 5000);
  EXPECT_EQ(r.first_frame(), 3000);
  std::vector<float> got(2000);
  ASSERT_EQ(r.copy(3000, got.data(), 2000), 2000);
  for (int i = 0; i < 2000; ++i) ASSERT_EQ(got[static_cast<size_t>(i)], static_cast<float>(3000 + i)) << i;
  EXPECT_EQ(r.copy(2999, got.data(), 10), 0);   // already overwritten
}

TEST(ReplayRing, CountsFramesFromTheSessionStartSoFramesMatchTheEnginesClock) {
  ReplayRing r;
  int64_t f = 0;
  ramp(r, f, 500);   // not armed: counted, not kept
  ASSERT_TRUE(r.arm(1000, 60.0));
  ramp(r, f, 300);
  r.freeze();
  EXPECT_EQ(r.first_frame(), 500);
  EXPECT_EQ(r.end_frame(), 800);
  float v = 0;
  ASSERT_EQ(r.copy(650, &v, 1), 1);
  EXPECT_EQ(v, 650.f);
  EXPECT_EQ(r.frame_of_seconds(0.65), 650);   // the engine's t (seconds since the session's first frame) to a frame
}

TEST(ReplayRing, ANotesSlicePlaysItsOwnSamplesWithShortFades) {
  ReplayRing r;
  ASSERT_TRUE(r.arm(1000, 60.0));
  int64_t f = 0;
  ramp(r, f, 3000);
  EXPECT_FALSE(r.play(100, 200));   // not frozen yet: no playback during a run
  r.freeze();
  ASSERT_TRUE(r.play(1000, 1400));
  EXPECT_TRUE(r.playing());
  const auto out = drain(r);
  ASSERT_GE(out.size(), 400u);
  const int fade = r.fade_frames();   // 5 ms
  EXPECT_EQ(fade, 5);
  for (int i = fade; i < 400 - fade; ++i) ASSERT_EQ(out[static_cast<size_t>(i)], static_cast<float>(1000 + i)) << i;
  EXPECT_LT(std::fabs(out[0]), 1000.f);   // fading in
  EXPECT_LT(std::fabs(out[399]), 1399.f);   // fading out
  for (size_t i = 400; i < out.size(); ++i) ASSERT_EQ(out[i], 0.f) << i;   // the rest of the last block is silence
  EXPECT_FALSE(r.playing());
}

TEST(ReplayRing, PlayIsClampedToWhatIsKept) {
  ReplayRing r;
  ASSERT_TRUE(r.arm(1000, 1.0));
  int64_t f = 0;
  ramp(r, f, 2500);
  r.freeze();
  ASSERT_TRUE(r.play(0, 9999));   // clamped to [1500, 2500)
  EXPECT_EQ(drain(r, 1000).size(), 1000u);
  EXPECT_FALSE(r.play(100, 200));   // nothing of it is kept
  EXPECT_FALSE(r.play(2400, 2400));
}

TEST(ReplayRing, StopPlaybackSilencesAtOnce) {
  ReplayRing r;
  ASSERT_TRUE(r.arm(1000, 60.0));
  int64_t f = 0;
  ramp(r, f, 2000);
  r.freeze();
  ASSERT_TRUE(r.play(0, 2000));
  float b[64];
  ASSERT_TRUE(r.on_output(b, 64));
  r.stop_playback();
  EXPECT_FALSE(r.playing());
  EXPECT_FALSE(r.on_output(b, 64));
}

TEST(ReplayRing, AFrozenRingKeepsNothingMore) {
  ReplayRing r;
  ASSERT_TRUE(r.arm(1000, 60.0));
  int64_t f = 0;
  ramp(r, f, 1000);
  r.freeze();
  EXPECT_TRUE(r.frozen());
  ramp(r, f, 1000);
  EXPECT_EQ(r.end_frame(), 1000);
}

TEST(ReplayRing, ReleaseZeroesTheAudioBeforeFreeingItAndIsIdempotent) {
  Spy spy;
  ReplayRing r(spy.a());
  ASSERT_TRUE(r.arm(1000, 60.0));
  int64_t f = 0;
  ramp(r, f, 5000);
  r.freeze();
  ASSERT_TRUE(r.play(0, 5000));
  r.release();
  EXPECT_EQ(spy.releases, 1);
  EXPECT_TRUE(spy.zero_at_release);
  EXPECT_FALSE(r.armed());
  EXPECT_FALSE(r.playing());
  float b[16];
  EXPECT_FALSE(r.on_output(b, 16));
  EXPECT_EQ(r.copy(0, b, 16), 0);
  r.release();
  EXPECT_EQ(spy.releases, 1);
}

TEST(ReplayRing, ArmingAgainReleasesAndZeroesTheOldRun) {
  Spy spy;
  ReplayRing r(spy.a());
  ASSERT_TRUE(r.arm(1000, 60.0));
  int64_t f = 0;
  ramp(r, f, 3000);
  ASSERT_TRUE(r.arm(1000, 60.0));   // a new run
  EXPECT_EQ(spy.allocs, 2);
  EXPECT_EQ(spy.releases, 1);
  EXPECT_TRUE(spy.zero_at_release);
  EXPECT_FALSE(r.frozen());
  ramp(r, f, 10);
  r.freeze();
  EXPECT_EQ(r.first_frame(), 3000);   // the new run starts where the session is now
}

TEST(ReplayRing, TheDestructorReleasesAndZeroes) {
  Spy spy;
  {
    ReplayRing r(spy.a());
    ASSERT_TRUE(r.arm(1000, 60.0));
    int64_t f = 0;
    ramp(r, f, 3000);
  }
  EXPECT_EQ(spy.releases, 1);
  EXPECT_TRUE(spy.zero_at_release);
}

TEST(ReplayRing, ReleaseWhileTheAudioThreadsRunIsSafe) {
  // The input thread records and the output thread plays while the UI thread arms, freezes, plays and releases over and over.
  // TSan (the sanitizer job) checks the handoff; here: no crash, and every release is zeroed.
  Spy spy;
  ReplayRing r(spy.a());
  std::atomic<bool> stop{false};
  std::thread in([&] {
    std::vector<float> b(48, 0.5f);
    while (!stop.load()) r.on_input(b.data(), 48);
  });
  std::thread out([&] {
    float b[48];
    while (!stop.load()) r.on_output(b, 48);
  });
  for (int i = 0; i < 200; ++i) {
    ASSERT_TRUE(r.arm(48000, 0.05));
    std::this_thread::yield();
    r.freeze();
    r.play(r.first_frame(), r.end_frame());
    std::this_thread::yield();
    r.release();
  }
  stop = true;
  in.join();
  out.join();
  EXPECT_EQ(spy.releases, 200);
  EXPECT_TRUE(spy.zero_at_release);
}

// ---- in the pump ----------------------------------------------------------------------------------------------------------
namespace {
struct Fake {
  int process_calls = 0;
  int drone_calls = 0;
  static void process(void* c, const float*, int) { ++static_cast<Fake*>(c)->process_calls; }
  static void drone(void* c, float* out, int n) {
    ++static_cast<Fake*>(c)->drone_calls;
    for (int i = 0; i < n; ++i) out[i] = 0.25f;
  }
  EngineOps ops() { return EngineOps{this, &Fake::process, &Fake::drone}; }
};
}  // namespace

TEST(PumpReplay, ARunIsRecordedAndAfterItTheMicrophoneReachesNeitherTheEngineNorTheRing) {
  Fake fk;
  PumpConfig pc;
  pc.sample_rate = 1000;
  pc.hop_size = 1000;
  AudioPump p(fk.ops(), pc);
  ASSERT_TRUE(p.replay().arm(1000, 60.0));
  std::vector<float> in(100, 0.1f);
  for (int i = 0; i < 10; ++i) p.on_input(in.data(), 100);
  EXPECT_EQ(fk.process_calls, 10);
  p.replay().freeze();   // the run ended: review
  for (int i = 0; i < 10; ++i) p.on_input(in.data(), 100);
  EXPECT_EQ(fk.process_calls, 10);   // the engine grades nothing more, playback included
  EXPECT_EQ(p.replay().end_frame(), 1000);
}

TEST(PumpReplay, PlaybackReplacesTheDroneAndTheDroneComesBackAfterIt) {
  Fake fk;
  PumpConfig pc;
  pc.sample_rate = 1000;
  AudioPump p(fk.ops(), pc);
  p.set_drone_enabled(true);
  ASSERT_TRUE(p.replay().arm(1000, 60.0));
  std::vector<float> in(100, 0.5f);
  for (int i = 0; i < 5; ++i) p.on_input(in.data(), 100);
  p.replay().freeze();
  ASSERT_TRUE(p.replay().play(0, 100));
  EXPECT_TRUE(p.output_wanted());
  std::vector<float> out(100, -1.f);
  p.on_output(out.data(), 100);
  EXPECT_EQ(fk.drone_calls, 0);
  EXPECT_EQ(out[50], 0.5f);
  p.on_output(out.data(), 100);
  EXPECT_EQ(fk.drone_calls, 1);
  EXPECT_EQ(out[50], 0.25f);
}

TEST(PumpReplay, OutputIsWantedOnlyForTheDroneOrAPlayback) {
  Fake fk;
  AudioPump p(fk.ops(), PumpConfig{});
  EXPECT_FALSE(p.output_wanted());
  p.set_drone_enabled(true);
  EXPECT_TRUE(p.output_wanted());
  p.set_drone_enabled(false);
  EXPECT_FALSE(p.output_wanted());
}

TEST(PumpReplay, ReleasingReturnsTheMicrophoneToTheEngine) {
  Fake fk;
  AudioPump p(fk.ops(), PumpConfig{});
  ASSERT_TRUE(p.replay().arm(48000, 1.0));
  p.replay().freeze();
  std::vector<float> in(256, 0.f);
  p.on_input(in.data(), 256);
  EXPECT_EQ(fk.process_calls, 0);
  p.replay().release();
  p.on_input(in.data(), 256);
  EXPECT_EQ(fk.process_calls, 1);
}

#ifdef __linux__
namespace {
// The open file descriptors of this process that point at regular files (not pipes, sockets or devices).
int regular_file_fds() {
  int count = 0;
  DIR* d = opendir("/proc/self/fd");
  if (!d) return -1;
  while (dirent* e = readdir(d)) {
    if (e->d_name[0] == '.') continue;
    struct stat st{};
    const std::string path = std::string("/proc/self/fd/") + e->d_name;
    if (stat(path.c_str(), &st) == 0 && S_ISREG(st.st_mode)) ++count;
  }
  closedir(d);
  return count;
}
}  // namespace

TEST(ReplayRing, AWholeRunAndReviewOpensNoFile) {
  // ADR 0013: never written to disk. The shared C++ (the ring in the pump) runs a run, a review with playback and the release with
  // no file opened at any point.
  Fake fk;
  AudioPump p(fk.ops(), PumpConfig{});
  const int before = regular_file_fds();
  ASSERT_GE(before, 0);
  ASSERT_TRUE(p.replay().arm(48000, 60.0));
  std::vector<float> in(480, 0.2f), out(480);
  for (int i = 0; i < 1000; ++i) {
    p.on_input(in.data(), 480);
    if (i % 100 == 0) {
      EXPECT_EQ(regular_file_fds(), before);
    }
  }
  p.replay().freeze();
  ASSERT_TRUE(p.replay().play(p.replay().first_frame(), p.replay().end_frame()));
  while (p.replay().playing()) p.on_output(out.data(), 480);
  EXPECT_EQ(regular_file_fds(), before);
  p.replay().release();
  EXPECT_EQ(regular_file_fds(), before);
}
#endif
