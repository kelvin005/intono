#include <gtest/gtest.h>

#include "post.hpp"
#include "test_util.hpp"
#include "tuning.hpp"
#include "yin.hpp"

using namespace intono;

static YinResult analyse_mid(double sr, const std::vector<float>& x, int win = 1024) {
  Yin yin(sr, win, 180, 3200, 0.12);
  EXPECT_TRUE(yin.ok());
  const size_t start = x.size() / 2;
  return yin.analyze(x.data() + start);
}

TEST(Yin, SineAccuracyAcrossTheViolinRange) {
  // G3, A4, E5, E6 and E7 (top of the supported range), both common sample rates
  for (double sr : {48000.0, 44100.0}) {
    for (double f : {196.0, 440.0, 659.26, 1318.5, 2637.0}) {
      const YinResult r = analyse_mid(sr, testutil::sine(sr, f, 1.0));
      ASSERT_TRUE(r.found) << f << "@" << sr;
      // Parabolic interpolation is biased at short lags: E7 is only ~18 samples per period, so it
      // gets a looser (still under the 3 c MAE target) bound than the rest of the range.
      EXPECT_NEAR(cents_between(r.hz, f), 0.0, f > 2000 ? 3.0 : 0.5) << f << "@" << sr;
      EXPECT_GT(r.confidence, 0.95) << f << "@" << sr;
    }
  }
}

TEST(Yin, DetuneResolutionIsFinerThanOneCent) {
  for (double c : {-50.0, -13.7, -1.0, 1.0, 7.8, 33.0}) {
    const double f = 440.0 * std::exp2(c / 1200);
    const YinResult r = analyse_mid(48000, testutil::sine(48000, f, 1.0));
    EXPECT_NEAR(cents_between(r.hz, f), 0.0, 0.5) << c;
  }
}

TEST(Yin, WeakFundamentalStillFindsTheFundamental) {
  const YinResult r = analyse_mid(48000, testutil::harmonic(48000, 196.0, 1.0, 0.2));
  ASSERT_TRUE(r.found);
  EXPECT_NEAR(cents_between(r.hz, 196.0), 0.0, 3.0);
}

TEST(Yin, NoiseIsNotVoiced) {
  uint32_t s = 1;
  std::vector<float> x(48000);
  for (auto& v : x) v = static_cast<float>(0.3 * testutil::noise(s));
  EXPECT_FALSE(analyse_mid(48000, x).found);
}

TEST(Yin, SilenceDoesNotCrashOrClaimPitch) {
  EXPECT_FALSE(analyse_mid(48000, std::vector<float>(48000, 0.f)).found);
}

TEST(Yin, RejectsWindowTooShortForMinHz) {
  EXPECT_FALSE(Yin(48000, 512, 180, 3200, 0.12).ok());   // needs window > 2 * sr / min_hz
  EXPECT_TRUE(Yin(48000, 1024, 180, 3200, 0.12).ok());
}

TEST(OctaveGuard, FoldsUnconfirmedJumpsBack) {
  OctaveGuard g;
  for (int i = 0; i < 5; ++i) EXPECT_NEAR(g.update(true, 440.0, 0.95), 440.0, 1e-9);
  EXPECT_NEAR(g.update(true, 880.0, 0.5), 440.0, 1e-9);    // low confidence: folded back
  EXPECT_NEAR(g.update(true, 220.0, 0.99), 440.0, 1e-9);   // 1st confident frame: still held
  EXPECT_NEAR(g.update(true, 220.0, 0.99), 440.0, 1e-9);   // 2nd
  EXPECT_NEAR(g.update(true, 220.0, 0.99), 220.0, 1e-9);   // 3rd confident frame: accepted
  EXPECT_NEAR(g.update(true, 220.0, 0.5), 220.0, 1e-9);    // new reference is 220
}

TEST(OctaveGuard, ConfidenceDipResetsTheStreak) {
  OctaveGuard g;
  g.update(true, 440.0, 0.95);
  g.update(true, 880.0, 0.99);
  g.update(true, 880.0, 0.99);
  EXPECT_NEAR(g.update(true, 880.0, 0.7), 440.0, 1e-9);  // dip: streak resets, still folded
  EXPECT_NEAR(g.update(true, 880.0, 0.99), 440.0, 1e-9);
}

TEST(OctaveGuard, RealIntervalsAreNotTouchedAndSilenceResets) {
  OctaveGuard g;
  g.update(true, 440.0, 0.9);
  EXPECT_NEAR(g.update(true, 660.0, 0.9), 660.0, 1e-9);   // a fifth is not an octave jump
  EXPECT_NEAR(g.update(false, 0.0, 0.0), 0.0, 1e-9);
  EXPECT_NEAR(g.update(true, 880.0, 0.3), 880.0, 1e-9);   // after silence a new note starts unguarded
}

namespace {
constexpr double kHop = 256.0 / 48000.0;
// Pitch contour in cents around a centre, fed one hop at a time; returns the last output.
CentreOut run_contour(CentreTracker& t, double centre_hz, double vib_hz, double amp_c, double secs, double phase = 0.0,
                      std::vector<CentreOut>* all = nullptr) {
  CentreOut o;
  const int n = static_cast<int>(secs / kHop);
  for (int i = 0; i < n; ++i) {
    const double c = amp_c * std::sin(2 * testutil::kPi * vib_hz * i * kHop + phase);
    o = t.update(true, centre_hz * std::exp2(c / 1200));
    if (all) all->push_back(o);
  }
  return o;
}
}  // namespace

TEST(CentreTracker, SteadyNoteGivesItsPitchAndNoVibrato) {
  CentreTracker t(kHop);
  const CentreOut o = run_contour(t, 440.0, 0.0, 0.0, 0.5);
  EXPECT_NEAR(cents_between(o.hz, 440.0), 0.0, 0.01);
  EXPECT_EQ(o.vib_rate, 0.0);
}

TEST(CentreTracker, VibratoCentreIsRecoveredAtEveryRateAndWidth) {
  for (double rate : {4.0, 5.5, 8.0}) {
    for (double pp : {12.0, 40.0, 80.0}) {
      CentreTracker t(kHop);
      std::vector<CentreOut> all;
      run_contour(t, 450.0, rate, pp / 2, 1.0, 0.7, &all);
      double worst = 0;
      for (size_t i = static_cast<size_t>(0.35 / kHop); i < all.size(); ++i) worst = std::max(worst, std::fabs(cents_between(all[i].hz, 450.0)));
      // Known limit (ADR 0001): a 4 Hz vibrato fills the whole 250 ms contour, so a narrow one often
      // has fewer than two confirmed extrema and falls back to the 150 ms median. Its worst frame is
      // then up to ~3.5 c, still inside the 5 c vibrato target; vibrato values are not guaranteed there.
      const bool slow_narrow = rate < 5.0 && pp < 20.0;
      EXPECT_LT(worst, slow_narrow ? 4.5 : 3.0) << rate << " Hz, " << pp << " c";
      if (!slow_narrow) {
        EXPECT_NEAR(all.back().vib_rate, rate, 0.8) << rate << " Hz, " << pp << " c";
        EXPECT_NEAR(all.back().vib_width, pp, 4.0) << rate << " Hz, " << pp << " c";
      }
    }
  }
}

TEST(CentreTracker, SmallPitchWobbleIsNotVibrato) {
  // +-3 c jitter (below the 8 c swing guard) must never be reported as vibrato
  CentreTracker t(kHop);
  uint32_t s = 5;
  int vib = 0;
  for (int i = 0; i < 400; ++i) {
    const CentreOut o = t.update(true, 440.0 * std::exp2(3.0 * testutil::noise(s) / 1200));
    vib += o.vib_rate > 0;
    if (i > 40) { EXPECT_NEAR(cents_between(o.hz, 440.0), 0.0, 3.5); }
  }
  EXPECT_EQ(vib, 0);
}

TEST(CentreTracker, SilenceStartsANewRun) {
  CentreTracker t(kHop);
  run_contour(t, 440.0, 0.0, 0.0, 0.3);
  EXPECT_EQ(t.update(false, 0.0).hz, 0.0);
  const CentreOut o = t.update(true, 330.0);  // first frame of the next note: no stale history
  EXPECT_NEAR(cents_between(o.hz, 330.0), 0.0, 1e-6);
}

TEST(CentreTracker, GlissandoFollowsWithoutFalseVibrato) {
  CentreTracker t(kHop);
  CentreOut o;
  int vib = 0;
  for (int i = 0; i < 300; ++i) {
    o = t.update(true, 440.0 * std::exp2((i * 0.5) / 1200));  // 94 c per second slide
    vib += o.vib_rate > 0;
  }
  EXPECT_EQ(vib, 0);
  EXPECT_NEAR(cents_between(o.hz, 440.0), 0.5 * 300 - 0.5 * 14, 6.0);  // median lags by ~half the 150 ms window
}

// ---- Hold-over must not survive a note change (ADR 0001, hold-over rule) ----------------

TEST(CentreTracker, JumpToSteadyNoteAfterVibratoShowsNoStaleCentre) {
  // Jump (over 50 c, no silence between) from a vibrato note to a steady note. The jump is
  // tried at every phase of the vibrato cycle, so it lands both while the centre is confirmed
  // and while the hold-over is active. Every frame at and after the jump must show the NEW pitch.
  for (double jump_c : {60.0, 100.0, -80.0, 300.0, -700.0}) {
    for (int extra = 0; extra < 40; ++extra) {  // 40 frames > one full 5.5 Hz cycle (34 frames)
      CentreTracker t(kHop);
      const CentreOut before = run_contour(t, 450.0, 5.5, 30.0, 0.6 + extra * kHop);
      ASSERT_GT(before.vib_rate, 0.0) << "vibrato must be established before the jump";
      const double fresh = 450.0 * std::exp2(jump_c / 1200);
      for (int i = 0; i < 60; ++i) {
        const CentreOut o = t.update(true, fresh);
        ASSERT_NEAR(cents_between(o.hz, fresh), 0.0, 0.01) << "jump " << jump_c << " c, phase " << extra << ", frame " << i;
        ASSERT_EQ(o.vib_rate, 0.0) << "stale vibrato rate after jump " << jump_c << ", phase " << extra << ", frame " << i;
        ASSERT_EQ(o.vib_width, 0.0) << "stale vibrato width after jump " << jump_c << ", phase " << extra << ", frame " << i;
      }
    }
  }
}

TEST(CentreTracker, JumpToNewVibratoNoteConvergesAndNeverShowsTheOldCentre) {
  for (double jump_c : {100.0, -100.0, 500.0}) {
    for (int extra = 0; extra < 40; extra += 3) {
      CentreTracker t(kHop);
      run_contour(t, 450.0, 5.5, 30.0, 0.6 + extra * kHop);
      const double fresh = 450.0 * std::exp2(jump_c / 1200);
      std::vector<CentreOut> all;
      run_contour(t, fresh, 6.5, 20.0, 0.5, 1.1, &all);
      for (size_t i = 0; i < all.size(); ++i) {
        // never closer to the old centre than the new vibrato's own excursion allows
        ASSERT_LE(std::fabs(cents_between(all[i].hz, fresh)), 21.0) << "jump " << jump_c << ", phase " << extra << ", frame " << i;
      }
      for (size_t i = static_cast<size_t>(0.35 / kHop); i < all.size(); ++i)
        ASSERT_NEAR(cents_between(all[i].hz, fresh), 0.0, 3.0) << "jump " << jump_c << ", phase " << extra << ", frame " << i;
    }
  }
}

TEST(CentreTracker, VibratoItselfNeverTriggersANoteChange) {
  // Steepest allowed vibrato (8 Hz, 100 c peak to peak) moves ~13 c per frame: far below the reset step.
  CentreTracker t(kHop);
  std::vector<CentreOut> all;
  run_contour(t, 450.0, 8.0, 50.0, 1.0, 0.3, &all);
  for (size_t i = static_cast<size_t>(0.4 / kHop); i < all.size(); ++i) {
    ASSERT_GT(all[i].vib_rate, 0.0) << i;
    ASSERT_NEAR(cents_between(all[i].hz, 450.0), 0.0, 3.0) << i;
  }
}

// ---- Portamento: the display must follow a slide, not hold the old centre ----------------

namespace {
// Feeds `n` frames of a linear pitch ramp (cents re `base_hz`) from `from_c` to `to_c`.
std::vector<CentreOut> feed_ramp(CentreTracker& t, double base_hz, double from_c, double to_c, int n, std::vector<double>* truth_c) {
  std::vector<CentreOut> out;
  for (int i = 1; i <= n; ++i) {
    const double c = from_c + (to_c - from_c) * i / n;
    out.push_back(t.update(true, base_hz * std::exp2(c / 1200)));
    if (truth_c) truth_c->push_back(c);
  }
  return out;
}
double cents_of(double hz, double base) { return cents_between(hz, base); }
constexpr int kSlideFrames = 28;  // 150 ms at 256 / 48000
}  // namespace

TEST(CentreTracker, PortamentoAfterVibratoFollowsTheSlide) {
  // Vibrato note (5.5 Hz, +-30 c), then a 200 c portamento over 150 ms, then the new note.
  // Tried at every phase of the vibrato so the slide starts anywhere in the cycle.
  for (int extra = 0; extra < 34; ++extra) {
    CentreTracker t(kHop);
    run_contour(t, 450.0, 5.5, 30.0, 0.6 + extra * kHop);
    const double end_c = 30.0 * std::sin(2 * testutil::kPi * 5.5 * static_cast<int>((0.6 + extra * kHop) / kHop) * kHop);
    std::vector<double> truth;
    const auto slide = feed_ramp(t, 450.0, end_c, 200.0, kSlideFrames, &truth);
    double prev = -1e9;
    for (int i = 0; i < kSlideFrames; ++i) {
      const double shown = cents_of(slide[i].hz, 450.0);
      // At most ~70 c (about 50 ms) behind the real pitch, then it catches up. Holding the old centre (0)
      // would fall further behind every frame; a vibrato that ended at its trough is the worst case.
      ASSERT_LT(truth[i] - shown, 70.0) << "phase " << extra << ", slide frame " << i << ": shown " << shown << ", true " << truth[i];
      ASSERT_LT(shown, std::max(truth[i], 0.0) + 20.0) << "phase " << extra << ", slide frame " << i;   // and never runs ahead of it (the old centre is the floor of "ahead")
      // once it has started to follow it never goes back toward the old centre
      ASSERT_GE(shown, prev - 3.0) << "phase " << extra << ", slide frame " << i;
      prev = std::max(prev, shown);
    }
    // hold the new note: converges within 120 ms, and no vibrato or old centre is left over
    std::vector<CentreOut> after;
    for (int i = 0; i < 60; ++i) after.push_back(t.update(true, 450.0 * std::exp2(200.0 / 1200)));
    for (int i = 0; i < 60; ++i) {
      if (i >= 22) { ASSERT_NEAR(cents_of(after[i].hz, 450.0), 200.0, 3.0) << "phase " << extra << ", frame " << i << " after the slide"; }
      if (i >= 12) { ASSERT_EQ(after[i].vib_rate, 0.0) << "phase " << extra << ", frame " << i; }
    }
  }
}

TEST(CentreTracker, PortamentoAfterSteadyNoteFollowsTheSlide) {
  CentreTracker t(kHop);
  run_contour(t, 450.0, 0.0, 0.0, 0.5);
  std::vector<double> truth;
  const auto slide = feed_ramp(t, 450.0, 0.0, 200.0, kSlideFrames, &truth);
  for (int i = 0; i < kSlideFrames; ++i)
    ASSERT_LT(truth[i] - cents_of(slide[i].hz, 450.0), 45.0) << "slide frame " << i;
  for (int i = 0; i < 40; ++i) {
    const CentreOut o = t.update(true, 450.0 * std::exp2(200.0 / 1200));
    if (i >= 22) { ASSERT_NEAR(cents_of(o.hz, 450.0), 200.0, 3.0) << i; }
  }
}

TEST(CentreTracker, VibratoStartingOnASteadyNoteDoesNotWobbleTheDisplay) {
  // The slide fix must not mistake the start of a vibrato for a slide and then chase it with the needle.
  for (double rate : {4.5, 5.5, 7.0}) {
    CentreTracker t(kHop);
    run_contour(t, 450.0, 0.0, 0.0, 0.5);
    std::vector<CentreOut> all;
    run_contour(t, 450.0, rate, 35.0, 1.2, 0.0, &all);
    for (size_t i = 0; i < all.size(); ++i) {
      const double shown = cents_of(all[i].hz, 450.0);
      ASSERT_LT(std::fabs(shown), 40.0) << rate << " Hz, frame " << i;                       // never outside the vibrato
      if (i >= static_cast<size_t>(0.55 / kHop)) { ASSERT_LT(std::fabs(shown), 4.0) << rate << " Hz, frame " << i; }  // settled, steady
    }
  }
}
