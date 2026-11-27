// ScoreCursor (ADR 0014): where the player is in the expected sequence, and when the score bias is on. Written before the cursor.
#include <gtest/gtest.h>

#include <vector>

#include "../src/score_cursor.hpp"

using intono::ScoreCursor;

namespace {
ScoreCursor with(std::vector<int> seq) {
  ScoreCursor c;
  c.set(seq.data(), static_cast<int>(seq.size()));
  return c;
}
std::vector<std::pair<int, int>> pairs(const ScoreCursor& c) {
  int from[ScoreCursor::kAhead], to[ScoreCursor::kAhead];
  const int n = c.pairs(from, to);
  std::vector<std::pair<int, int>> out;
  for (int i = 0; i < n; ++i) out.emplace_back(from[i], to[i]);
  return out;
}
const std::vector<int> kScale = {55, 57, 59, 60, 62, 64, 66, 67, 66, 64, 62, 60, 59, 57, 55};   // G major, 1 octave
}  // namespace

TEST(ScoreCursor, EmptyOrUnsetIsFreeMode) {
  ScoreCursor c;
  EXPECT_FALSE(c.biased());
  EXPECT_TRUE(pairs(c).empty());
  c.set(nullptr, 5);
  EXPECT_FALSE(c.biased());
  auto d = with({60, 62});
  d.set(nullptr, 0);   // n = 0 returns to free mode
  EXPECT_FALSE(d.biased());
  EXPECT_TRUE(pairs(d).empty());
}

TEST(ScoreCursor, PairsAreTheNextStepsOfTheScaleAheadOfTheCursor) {
  auto c = with(kScale);
  EXPECT_TRUE(c.biased());
  EXPECT_EQ(c.k(), 0);
  // before the first note: the steps into notes 1..4 (the decoder runs about 213 ms ahead of the emitted notes)
  EXPECT_EQ(pairs(c), (std::vector<std::pair<int, int>>{{55, 57}, {57, 59}, {59, 60}, {60, 62}}));
  c.on_note(55);
  c.on_note(57);
  EXPECT_EQ(c.k(), 2);
  EXPECT_EQ(pairs(c), (std::vector<std::pair<int, int>>{{57, 59}, {59, 60}, {60, 62}, {62, 64}}));
}

TEST(ScoreCursor, NearTheEndThePairsRunOut) {
  auto c = with({60, 62, 64});
  c.on_note(60);
  c.on_note(62);
  EXPECT_EQ(pairs(c), (std::vector<std::pair<int, int>>{{62, 64}}));
  c.on_note(64);
  EXPECT_EQ(c.k(), 3);
  EXPECT_TRUE(pairs(c).empty());
}

TEST(ScoreCursor, AMatchAdvancesOneAndOneMissedNoteIsSkipped) {
  auto c = with(kScale);
  c.on_note(55);
  EXPECT_EQ(c.k(), 1);
  c.on_note(59);   // A3 missed: B3 is expected[k+1]
  EXPECT_EQ(c.k(), 3);
  EXPECT_TRUE(c.biased());
}

TEST(ScoreCursor, TwoMissedNotesAreNotSkipped) {
  auto c = with(kScale);
  c.on_note(55);
  c.on_note(60);   // C4 is expected[k+2]: at most one skip, so this is a miss of the window
  EXPECT_EQ(c.k(), 1);
  EXPECT_EQ(c.misses(), 1);
  EXPECT_TRUE(c.biased());
}

TEST(ScoreCursor, AMatchResetsTheMissCount) {
  auto c = with(kScale);
  c.on_note(55);
  c.on_note(70);
  c.on_note(71);
  EXPECT_EQ(c.misses(), 2);
  c.on_note(57);
  EXPECT_EQ(c.misses(), 0);
  EXPECT_EQ(c.k(), 2);
}

TEST(ScoreCursor, ThreeConsecutiveMissesDropTheBias) {
  auto c = with(kScale);
  c.on_note(55);
  c.on_note(70);
  c.on_note(71);
  EXPECT_TRUE(c.biased());
  c.on_note(72);   // the 3rd consecutive note outside the window
  EXPECT_FALSE(c.biased());
  EXPECT_TRUE(pairs(c).empty()) << "plain segmentation: no bias at all";
}

TEST(ScoreCursor, OneMatchingNoteDoesNotRestoreTheBias) {
  auto c = with(kScale);
  for (int m : {55, 70, 71, 72}) c.on_note(m);
  ASSERT_FALSE(c.biased());
  c.on_note(62);   // matches expected[4], but alone
  EXPECT_FALSE(c.biased());
  c.on_note(70);   // and the next does not follow it
  EXPECT_FALSE(c.biased());
}

TEST(ScoreCursor, TwoConsecutiveMatchesRestoreTheBiasAtThatPlace) {
  auto c = with(kScale);
  for (int m : {55, 70, 71, 72}) c.on_note(m);
  ASSERT_FALSE(c.biased());
  c.on_note(62);
  c.on_note(64);   // expected[4], expected[5]: back in the scale
  EXPECT_TRUE(c.biased());
  EXPECT_EQ(c.k(), 6);
  EXPECT_EQ(c.misses(), 0);
  EXPECT_EQ(pairs(c).front(), (std::pair<int, int>{64, 66}));
}

TEST(ScoreCursor, ResyncSearchesForwardFromTheCursorOnly) {
  auto c = with(kScale);
  for (int m : {55, 57, 59, 60, 62}) c.on_note(m);   // k = 5
  for (int m : {80, 81, 82}) c.on_note(m);           // lost
  ASSERT_FALSE(c.biased());
  c.on_note(57);
  c.on_note(59);   // A3 B3 appear only before the cursor (ascending) and at 13..12 descending: B3 then A3 is the descent's order
  EXPECT_FALSE(c.biased()) << "A3 -> B3 is behind the cursor; the descent has B3 -> A3";
  c.on_note(59);
  c.on_note(57);   // B3 A3: expected[12], expected[13]
  EXPECT_TRUE(c.biased());
  EXPECT_EQ(c.k(), 14);
}

TEST(ScoreCursor, ANewSequenceStartsAfresh) {
  auto c = with(kScale);
  for (int m : {55, 70, 71, 72}) c.on_note(m);
  ASSERT_FALSE(c.biased());
  const std::vector<int> d{62, 64, 66};
  c.set(d.data(), 3);
  EXPECT_TRUE(c.biased());
  EXPECT_EQ(c.k(), 0);
  EXPECT_EQ(c.misses(), 0);
}

TEST(ScoreCursor, LongSequencesAreCappedAndRepeatedPitchesMakeNoPair) {
  std::vector<int> big(300, 0);
  for (int i = 0; i < 300; ++i) big[i] = 55 + (i % 24);
  auto c = with(big);
  EXPECT_EQ(c.size(), ScoreCursor::kMax);
  auto r = with({60, 60, 62});
  EXPECT_EQ(pairs(r), (std::vector<std::pair<int, int>>{{60, 62}})) << "a repeated note is not a step";
}
