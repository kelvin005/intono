#include <gtest/gtest.h>

#include "tuning.hpp"

using namespace intono;

TEST(Tuning, CentsMaths) {
  EXPECT_NEAR(cents_between(880.0, 440.0), 1200.0, 1e-9);
  EXPECT_NEAR(cents_between(440.0, 880.0), -1200.0, 1e-9);
  EXPECT_NEAR(cents_between(442.0, 440.0), 7.8514, 1e-3);
  EXPECT_NEAR(midi_to_hz(69, 440), 440.0, 1e-9);
  EXPECT_NEAR(midi_to_hz(57, 440), 220.0, 1e-9);
  EXPECT_NEAR(midi_to_hz(69, 415), 415.0, 1e-9);  // baroque pitch
}

TEST(Tuning, EqualTemperamentNearestNote) {
  Target t = nearest_target(440.0, Tuning::Equal, 440.0, 60);
  EXPECT_EQ(t.midi_note, 69);
  EXPECT_NEAR(t.cents, 0.0, 1e-9);
  t = nearest_target(midi_to_hz(76, 440) * std::exp2(23.0 / 1200), Tuning::Equal, 440.0, 60);  // E5, +23c
  EXPECT_EQ(t.midi_note, 76);
  EXPECT_NEAR(t.cents, 23.0, 1e-6);
  t = nearest_target(midi_to_hz(76, 440) * std::exp2(-60.0 / 1200), Tuning::Equal, 440.0, 60);  // -60c rounds to the note below
  EXPECT_EQ(t.midi_note, 75);
  EXPECT_NEAR(t.cents, 40.0, 1e-6);
}

TEST(Tuning, A4Adjustable) {
  const Target t = nearest_target(442.0, Tuning::Equal, 442.0, 60);
  EXPECT_EQ(t.midi_note, 69);
  EXPECT_NEAR(t.cents, 0.0, 1e-9);
}

TEST(Tuning, JustMajorThirdIsFlatterThanEqual) {
  const double c4 = midi_to_hz(60, 440);
  const double pure_e = c4 * 5.0 / 4.0;
  Target t = nearest_target(pure_e, Tuning::Just, 440.0, 60);
  EXPECT_EQ(t.midi_note, 64);
  EXPECT_NEAR(t.cents, 0.0, 1e-9);                       // in tune against the drone
  t = nearest_target(pure_e, Tuning::Equal, 440.0, 60);  // ...but 13.69 c flat of equal-tempered E
  EXPECT_NEAR(t.cents, -13.686, 1e-2);
}

TEST(Tuning, JustHandlesOtherOctavesAndTonics) {
  const double d4 = midi_to_hz(62, 440);
  for (int o : {-2, -1, 0, 1, 2}) {
    const double f = d4 * 3.0 / 2.0 * std::exp2(o);  // perfect fifth above D, any octave
    const Target t = nearest_target(f, Tuning::Just, 440.0, 62);
    EXPECT_NEAR(t.cents, 0.0, 1e-9) << o;
  }
  const Target flat = nearest_target(d4 * 9.0 / 8.0 * std::exp2(-15.0 / 1200), Tuning::Just, 440.0, 62);
  EXPECT_NEAR(flat.cents, -15.0, 1e-6);
}

TEST(Tuning, PythagoreanFifthAndThird) {
  const double g3 = midi_to_hz(55, 440);
  Target t = nearest_target(g3 * 3.0 / 2.0, Tuning::Pythagorean, 440.0, 55);
  EXPECT_NEAR(t.cents, 0.0, 1e-9);
  t = nearest_target(g3 * 81.0 / 64.0, Tuning::Pythagorean, 440.0, 55);  // wide Pythagorean third
  EXPECT_NEAR(t.cents, 0.0, 1e-9);
  t = nearest_target(g3 * 5.0 / 4.0, Tuning::Pythagorean, 440.0, 55);   // pure third is 21.5 c flat of it
  EXPECT_NEAR(t.cents, -21.506, 1e-2);
}

TEST(Tuning, UnvoicedInputGivesEmptyTarget) {
  EXPECT_EQ(nearest_target(0.0, Tuning::Equal, 440.0, 60).midi_note, 0);
}
