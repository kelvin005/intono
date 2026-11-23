#include <gtest/gtest.h>

#include "filters.hpp"
#include "test_util.hpp"

using namespace intono;

static double gain_at(Biquad f, double hz, double sr) {
  double peak = 0;
  const int n = static_cast<int>(sr);  // 1 s: settles long before the last 0.25 s
  for (int i = 0; i < n; ++i) {
    const double y = f.process(std::sin(2 * testutil::kPi * hz * i / sr));
    if (i > n * 3 / 4) peak = std::max(peak, std::fabs(y));
  }
  return peak;
}

TEST(Filters, ButterworthIsMinus3dBAtCutoffAndFlatInPassband) {
  const double sr = 48000;
  const Biquad hp = Biquad::butter2(true, 150, sr), lp = Biquad::butter2(false, 4000, sr);
  EXPECT_NEAR(gain_at(hp, 150, sr), std::sqrt(0.5), 0.01);
  EXPECT_NEAR(gain_at(lp, 4000, sr), std::sqrt(0.5), 0.01);
  EXPECT_NEAR(gain_at(hp, 1000, sr), 1.0, 0.01);
  EXPECT_NEAR(gain_at(lp, 1000, sr), 1.0, 0.01);
}

TEST(Filters, HighpassRollsOffAt12dBPerOctave) {
  const double sr = 48000;
  const Biquad hp = Biquad::butter2(true, 150, sr);
  const double g75 = gain_at(hp, 75, sr), g37 = gain_at(hp, 37.5, sr);
  EXPECT_NEAR(g75, 0.2425, 0.01);        // 1/sqrt(1+(150/75)^4) for a 2nd-order Butterworth
  EXPECT_NEAR(g37 / g75, 0.25, 0.02);    // another octave down: x0.25 (12 dB)
}

TEST(Filters, DesignWorksAtOtherSampleRates) {
  for (double sr : {44100.0, 16000.0, 96000.0}) {
    EXPECT_NEAR(gain_at(Biquad::butter2(true, 150, sr), 150, sr), std::sqrt(0.5), 0.015) << sr;
  }
}

TEST(Filters, DcBlockerRemovesOffsetAndKeepsAudioBand) {
  DcBlocker dc;
  double y = 0;
  for (int i = 0; i < 48000; ++i) y = dc.process(1.0);
  EXPECT_NEAR(y, 0.0, 1e-3);
  dc.reset();
  double peak = 0;
  for (int i = 0; i < 48000; ++i) {
    const double o = dc.process(std::sin(2 * testutil::kPi * 440 * i / 48000.0));
    if (i > 40000) peak = std::max(peak, std::fabs(o));
  }
  EXPECT_NEAR(peak, 1.0, 0.02);
}
