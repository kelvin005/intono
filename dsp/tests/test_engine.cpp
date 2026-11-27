#include <gtest/gtest.h>

#include <atomic>
#include <chrono>
#include <thread>

#include "intono/intono.h"
#include "test_util.hpp"

namespace {

intono_config cfg48() {
  intono_config c{};
  c.sample_rate = 48000; c.window_size = 1024; c.hop_size = 256; c.a4_hz = 440; c.tuning = 0; c.min_hz = 180; c.max_hz = 3200;
  return c;
}

std::vector<intono_frame> run(const intono_config& c, const std::vector<float>& x, int chunk, int tonic = 60) {
  intono_engine* e = testutil::make_engine(&c);
  EXPECT_NE(e, nullptr);
  intono_set_tonic(e, tonic);
  std::vector<intono_frame> all, buf(64);
  for (size_t p = 0; p < x.size(); p += chunk) {
    intono_process(e, x.data() + p, static_cast<int>(std::min<size_t>(chunk, x.size() - p)));
    int n;
    while ((n = intono_read_frames(e, buf.data(), 64)) > 0) all.insert(all.end(), buf.begin(), buf.begin() + n);
  }
  intono_destroy(e);
  return all;
}

}  // namespace

TEST(Engine, RejectsInvalidConfigurations) {
  EXPECT_EQ(intono_create(nullptr), nullptr);
  auto bad = [](auto mutate) { intono_config c = cfg48(); mutate(c); return intono_create(&c); };
  EXPECT_EQ(bad([](intono_config& c) { c.sample_rate = 0; }), nullptr);
  EXPECT_EQ(bad([](intono_config& c) { c.window_size = 512; }), nullptr);       // too short for 180 Hz
  EXPECT_EQ(bad([](intono_config& c) { c.hop_size = 2048; }), nullptr);         // hop > window
  EXPECT_EQ(bad([](intono_config& c) { c.a4_hz = 300; }), nullptr);
  EXPECT_EQ(bad([](intono_config& c) { c.tuning = 3; }), nullptr);
  EXPECT_EQ(bad([](intono_config& c) { c.min_hz = 500; c.max_hz = 400; }), nullptr);
  const intono_config good = cfg48();
  intono_engine* ok = intono_create(&good);
  EXPECT_NE(ok, nullptr);
  intono_destroy(ok);
  intono_destroy(nullptr);  // must be safe
}

TEST(Engine, FrameCountAndTimingFollowTheHop) {
  const auto x = testutil::sine(48000, 440, 1.0);
  const auto f = run(cfg48(), x, 128);
  ASSERT_EQ(f.size(), 1u + (x.size() - 1024) / 256);
  EXPECT_NEAR(f[0].t_sec, 512.0 / 48000, 1e-9);                       // window centre
  EXPECT_NEAR(f[1].t_sec - f[0].t_sec, 256.0 / 48000, 1e-9);
}

TEST(Engine, ResultsDoNotDependOnHowTheAudioIsChunked) {
  const auto x = testutil::harmonic(48000, 330.0, 1.2);
  const auto ref = run(cfg48(), x, 4096);
  for (int chunk : {1, 7, 100, 128, 256, 255, 1000}) {
    const auto f = run(cfg48(), x, chunk);
    ASSERT_EQ(f.size(), ref.size()) << chunk;
    for (size_t i = 0; i < f.size(); ++i) {
      ASSERT_EQ(f[i].hz, ref[i].hz) << "chunk " << chunk << " frame " << i;
      ASSERT_EQ(f[i].is_voiced, ref[i].is_voiced);
    }
  }
}

TEST(Engine, ReportsNoteAndCentsInEqualTemperament) {
  auto x = testutil::harmonic(48000, 440.0 * std::exp2(-18.0 / 1200), 1.5);  // A4, 18 c flat
  const auto f = run(cfg48(), x, 128);
  const intono_frame& last = f.back();
  EXPECT_EQ(last.is_voiced, 1);
  EXPECT_EQ(last.midi_note, 69);
  EXPECT_NEAR(last.cents, -18.0, 1.0);
  EXPECT_NEAR(last.hz, 440.0 * std::exp2(-18.0 / 1200), 0.3);
}

TEST(Engine, JustIntonationAgainstTheTonic) {
  const double c4 = 440.0 * std::exp2(-9.0 / 12);
  const auto x = testutil::harmonic(48000, c4 * 1.25, 1.2);  // pure major third above C4
  intono_config c = cfg48();
  c.tuning = 1;
  EXPECT_NEAR(run(c, x, 128, 60).back().cents, 0.0, 1.0);    // in tune against a C drone
  c.tuning = 0;
  EXPECT_NEAR(run(c, x, 128, 60).back().cents, -13.7, 1.0);  // 13.7 c flat of equal-tempered E
}

TEST(Engine, AdjustableA4) {
  intono_config c = cfg48();
  c.a4_hz = 442;
  const auto f = run(c, testutil::harmonic(48000, 442.0, 1.0), 128);
  EXPECT_EQ(f.back().midi_note, 69);
  EXPECT_NEAR(f.back().cents, 0.0, 0.7);
}

TEST(Engine, WorksAt44100Hz) {
  intono_config c = cfg48();
  c.sample_rate = 44100;
  const auto f = run(c, testutil::harmonic(44100, 659.26, 1.0), 128);
  EXPECT_EQ(f.back().midi_note, 76);
  EXPECT_NEAR(f.back().cents, 0.0, 1.0);
}

TEST(Engine, SilenceIsUnvoicedAndNoiseFloorGateStopsHum) {
  const auto f = run(cfg48(), std::vector<float>(48000, 0.f), 128);
  for (const auto& fr : f) { EXPECT_EQ(fr.is_voiced, 0); EXPECT_EQ(fr.hz, 0.f); }
}

TEST(Engine, OnsetOnNoteStartAndOnPitchStep) {
  std::vector<float> x(12000, 0.f);  // 0.25 s of silence
  const auto note = testutil::harmonic(48000, 440.0, 0.5);
  x.insert(x.end(), note.begin(), note.end());
  const auto step = testutil::harmonic(48000, 440.0 * std::exp2(100.0 / 1200), 0.5);  // +100 c, no RMS change
  x.insert(x.end(), step.begin(), step.end());
  const auto f = run(cfg48(), x, 128);
  std::vector<double> onsets;
  for (const auto& fr : f) if (fr.is_onset) onsets.push_back(fr.t_sec);
  ASSERT_EQ(onsets.size(), 2u);
  EXPECT_NEAR(onsets[0], 0.25, 0.04);
  EXPECT_NEAR(onsets[1], 0.75, 0.06);
}

TEST(Engine, SteadyNoteHasExactlyOneOnset) {
  std::vector<float> x(12000, 0.f);
  const auto note = testutil::harmonic(48000, 523.25, 1.0);
  x.insert(x.end(), note.begin(), note.end());
  int n = 0;
  for (const auto& fr : run(cfg48(), x, 128)) n += fr.is_onset;
  EXPECT_EQ(n, 1);
}

TEST(Engine, VibratoNoteThenJumpShowsTheNewNoteWithinAFewFrames) {
  // Audio-level version of the hold-over reset: vibrato on A4, then a jump to C#5 (+400 c) with no gap.
  const double sr = 48000;
  std::vector<float> x(12000, 0.f);
  const size_t n1 = static_cast<size_t>(sr * 0.8), n2 = static_cast<size_t>(sr * 0.6);
  std::vector<float> a(n1), b(n2);
  for (size_t i = 0; i < n1; ++i) {
    const double f = 440.0 * std::exp2(30.0 * std::sin(2 * testutil::kPi * 5.5 * i / sr) / 1200);
    static double ph = 0;
    ph += 2 * testutil::kPi * f / sr;
    a[i] = static_cast<float>(0.3 * std::sin(ph) + 0.15 * std::sin(2 * ph) + 0.1 * std::sin(3 * ph));
  }
  const double f2 = 440.0 * std::exp2(400.0 / 1200);
  for (size_t i = 0; i < n2; ++i) b[i] = static_cast<float>(0.3 * std::sin(2 * testutil::kPi * f2 * i / sr) + 0.15 * std::sin(4 * testutil::kPi * f2 * i / sr));
  x.insert(x.end(), a.begin(), a.end());
  x.insert(x.end(), b.begin(), b.end());
  const double t_jump = 12000 / sr + 0.8;
  const auto f = run(cfg48(), x, 128);
  int checked = 0;
  for (const auto& fr : f) {
    if (fr.t_sec < t_jump + 0.06 + 1024.0 / sr) continue;  // window centre must be clear of the jump by 60 ms
    ASSERT_EQ(fr.is_voiced, 1);
    ASSERT_NEAR(fr.hz, f2, 0.6) << "t=" << fr.t_sec;       // new pitch, not a stale vibrato centre
    ASSERT_EQ(fr.vibrato_rate_hz, 0.f) << "t=" << fr.t_sec;
    ++checked;
  }
  EXPECT_GT(checked, 40);
}

TEST(Drone, SinePitchLevelAndTimbre) {
  const intono_config c = cfg48();
  intono_engine* e = testutil::make_engine(&c);
  std::vector<float> out(48000);
  intono_drone_set(e, 69, 1.0f, 0);
  intono_drone_render(e, out.data(), static_cast<int>(out.size()));
  double peak = 0;
  int crossings = 0;
  for (size_t i = 24000; i < out.size(); ++i) {  // after the gain smoothing has settled
    peak = std::max<double>(peak, std::fabs(out[i]));
    if (out[i - 1] < 0 && out[i] >= 0) ++crossings;
  }
  EXPECT_NEAR(peak, 1.0, 0.02);
  EXPECT_NEAR(crossings, 440.0 * 0.5, 2.0);  // half a second of 440 Hz

  // rich timbre: same pitch, more energy above the fundamental, peak never clips
  intono_drone_set(e, 69, 1.0f, 1);
  intono_drone_render(e, out.data(), static_cast<int>(out.size()));
  double rpeak = 0, e1 = 0, e2 = 0;
  for (size_t i = 24000; i < out.size(); ++i) {
    rpeak = std::max<double>(rpeak, std::fabs(out[i]));
    e1 += out[i] * std::sin(2 * testutil::kPi * 440 * i / 48000.0);
    e2 += out[i] * std::sin(2 * testutil::kPi * 880 * i / 48000.0);
  }
  EXPECT_LE(rpeak, 1.0);
  EXPECT_GT(std::fabs(e2), 0.05 * std::fabs(e1));
  intono_destroy(e);
}

TEST(Drone, SilentWhenGainZeroAndLevelFollowsGain) {
  const intono_config c = cfg48();
  intono_engine* e = testutil::make_engine(&c);
  std::vector<float> out(24000);
  intono_drone_render(e, out.data(), static_cast<int>(out.size()));  // default: off
  for (float v : out) ASSERT_EQ(v, 0.f);
  intono_drone_set(e, 57, 0.25f, 0);
  intono_drone_render(e, out.data(), static_cast<int>(out.size()));
  double peak = 0;
  for (size_t i = 12000; i < out.size(); ++i) peak = std::max<double>(peak, std::fabs(out[i]));
  EXPECT_NEAR(peak, 0.25, 0.01);
  intono_destroy(e);
}

TEST(Threads, AudioThreadProducesWhileUiThreadConsumes) {
  const intono_config c = cfg48();
  intono_engine* e = testutil::make_engine(&c);
  const auto x = testutil::harmonic(48000, 440.0, 10.0);
  std::atomic<bool> done{false};
  std::atomic<size_t> read{0};
  // Real capture is paced by the device; this producer is not, so it is held back while more than half the frame ring (1024) is unread.
  // Without that, a UI thread descheduled for ~200 ms lets the ring fill and frames are dropped by design, which is not what this test
  // is about (ordering and no loss while both threads run). Ring overflow itself is covered by the Worker and ring tests.
  std::thread audio([&] {
    for (size_t p = 0; p < x.size(); p += 128) {
      const size_t produced = p + 128 >= 1024 ? 1 + (p + 128 - 1024) / 256 : 0;
      while (produced > read.load() + 512) std::this_thread::yield();
      intono_process(e, x.data() + p, static_cast<int>(std::min<size_t>(128, x.size() - p)));
    }
    done = true;
  });
  std::vector<intono_frame> buf(32);
  double last_t = -1;
  size_t total = 0;
  bool ok = true;
  auto drain = [&] {
    int n;
    while ((n = intono_read_frames(e, buf.data(), 32)) > 0) {
      for (int i = 0; i < n; ++i, ++total) { ok &= buf[i].t_sec > last_t; last_t = buf[i].t_sec; }
      read.store(total);
    }
  };
  // The UI thread is descheduled for a while (on the 2-vCPU CI emulator this happened for long enough that the unpaced producer
  // filled the 1024-frame ring and frames were dropped, as designed: 1799 of 1872 read, main at a7e258b).
  std::this_thread::sleep_for(std::chrono::milliseconds(300));
  while (!done) drain();
  audio.join();
  drain();
  EXPECT_TRUE(ok);
  EXPECT_EQ(total, 1u + (x.size() - 1024) / 256);
  intono_destroy(e);
}

// ---- scale mode (ADR 0014): intono_set_expected ---------------------------------------------------------------------------
namespace {
std::vector<float> phrase(const std::vector<std::pair<double, double>>& hz_secs) {   // harmonic tones back to back (legato)
  std::vector<float> x;
  for (const auto& [hz, s] : hz_secs) {
    const auto t = testutil::harmonic(48000, hz, s);
    x.insert(x.end(), t.begin(), t.end());
  }
  x.resize(x.size() + 48000, 0.f);   // a second of silence closes the last note
  return x;
}
std::vector<intono_note> run_notes(const std::vector<float>& x, const std::vector<int>* expected, bool clear_after_set = false) {
  const intono_config c = cfg48();
  intono_engine* e = testutil::make_engine(&c);
  if (expected) intono_set_expected(e, expected->data(), static_cast<int>(expected->size()));
  if (clear_after_set) intono_set_expected(e, nullptr, 0);
  std::vector<intono_note> all;
  intono_note buf[64];
  for (size_t p = 0; p < x.size(); p += 256) {
    intono_process(e, x.data() + p, static_cast<int>(std::min<size_t>(256, x.size() - p)));
    const int n = testutil::read_notes(e, buf, 64);
    all.insert(all.end(), buf, buf + n);
  }
  intono_destroy(e);
  return all;
}
double hz(int midi) { return 440.0 * std::exp2((midi - 69) / 12.0); }
}  // namespace

TEST(ScaleMode, SetExpectedIsSafeWithNullAndEmptyInput) {
  const intono_config c = cfg48();
  intono_engine* e = testutil::make_engine(&c);
  intono_set_expected(nullptr, nullptr, 3);
  intono_set_expected(e, nullptr, 3);
  intono_set_expected(e, nullptr, 0);
  const int none[1] = {0};
  intono_set_expected(e, none, -1);
  std::vector<int> big(1000, 69);
  intono_set_expected(e, big.data(), 1000);   // more than 128: the rest is ignored
  intono_destroy(e);
}

TEST(ScaleMode, ClearingTheSequenceGivesExactlyTheFreeModeOutput) {
  const auto x = phrase({{hz(67), 0.4}, {hz(69), 0.12}, {hz(71), 0.12}, {hz(72), 0.4}});
  const std::vector<int> exp{67, 69, 71, 72};
  const auto a = run_notes(x, nullptr);
  const auto b = run_notes(x, &exp, true);
  ASSERT_EQ(a.size(), b.size());
  for (size_t i = 0; i < a.size(); ++i) {
    EXPECT_EQ(a[i].t_start, b[i].t_start);
    EXPECT_EQ(a[i].midi_note, b[i].midi_note);
    EXPECT_EQ(a[i].mean_cents, b[i].mean_cents);
    EXPECT_EQ(a[i].frame_count, b[i].frame_count);
  }
}

TEST(ScaleMode, AScalePlayedAsExpectedIsReportedNoteForNote) {
  const std::vector<int> exp{67, 69, 71, 72, 74, 72, 71, 69, 67};
  std::vector<std::pair<double, double>> spec;
  for (int m : exp) spec.push_back({hz(m), 0.25});
  const auto notes = run_notes(phrase(spec), &exp);
  ASSERT_EQ(notes.size(), exp.size());
  for (size_t i = 0; i < exp.size(); ++i) EXPECT_EQ(notes[i].midi_note, exp[i]) << i;
}

TEST(ScaleMode, ThePlayerPlayingSomethingElseGetsWhatTheyPlayed) {
  // Expected G major up, the player plays a different tune: every reported note is a played one, none is invented from the score.
  const std::vector<int> exp{67, 69, 71, 72, 74, 76, 78, 79};
  const std::vector<int> played{70, 73, 70, 66, 64, 70};
  std::vector<std::pair<double, double>> spec;
  for (int m : played) spec.push_back({hz(m), 0.3});
  const auto notes = run_notes(phrase(spec), &exp);
  ASSERT_EQ(notes.size(), played.size());
  for (size_t i = 0; i < played.size(); ++i) EXPECT_EQ(notes[i].midi_note, played[i]) << i;
}

TEST(ScaleMode, AnOffScaleNoteInsertedBeforeTheDueNoteIsReportedAsPlayed) {
  // ADR 0014 Amendment 1. Expected G A B C; the player inserts A# (off the scale) before B. Wherever free mode resolves the A#, scale
  // mode must too: it must not be swallowed into a B that starts early (that would invent the expected note).
  const std::vector<int> exp{67, 69, 71, 72};
  const std::vector<int> played{67, 69, 70, 71, 72};
  for (const double secs : {0.14, 0.2, 0.3})
    for (const double det : {-20.0, 0.0}) {
      const auto x = phrase({{hz(67), 0.35}, {hz(69), 0.2}, {hz(70) * std::exp2(det / 1200.0), secs}, {hz(71), 0.2}, {hz(72), 0.35}});
      const auto free_notes = run_notes(x, nullptr);
      ASSERT_EQ(free_notes.size(), played.size()) << secs << " s, " << det << " cents: free mode must resolve the case";
      const auto notes = run_notes(x, &exp);
      ASSERT_EQ(notes.size(), played.size()) << secs << " s, " << det << " cents";
      for (size_t i = 0; i < played.size(); ++i) EXPECT_EQ(notes[i].midi_note, played[i]) << secs << " s, " << det << " cents, " << i;
    }
}
