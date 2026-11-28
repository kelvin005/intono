#include <gtest/gtest.h>

#include "../src/notes_hmm.hpp"
#include "intono/intono.h"
#include "test_util.hpp"

namespace {

using intono::NoteFrame;
using intono::NoteSummary;
using intono::NoteTracker;

constexpr double kHop = 256.0 / 48000.0;

// Drives the tracker with one frame per call (pitch in cents re A4); collects emitted notes and when (frame index) they came out.
struct Driver {
  NoteTracker tr{20, 10, 2 * kHop};          // half a 1024-sample window = 2 hops
  std::vector<NoteSummary> notes;
  std::vector<int> emitted_at;
  int i = 0;
  void push(bool voiced, double c, bool rms, double vr, double vw) {
    NoteFrame f;
    f.t = i * kHop;
    f.c = c;
    f.ctr = c;
    f.conf = 0.95;
    f.vr = vr;
    f.vw = vw;
    NoteSummary out[NoteTracker::kMaxOut];
    const int n = tr.update(voiced, rms, f, c, out);
    for (int k = 0; k < n; ++k) {
      notes.push_back(out[k]);
      emitted_at.push_back(i);
    }
    ++i;
  }
  void voiced(double c, bool rms = false, double vr = 0, double vw = 0) { push(true, c, rms, vr, vw); }
  void run(double c, int n) { for (int k = 0; k < n; ++k) voiced(c); }
  void silent(int n = 1) { for (int k = 0; k < n; ++k) push(false, 0, false, 0, 0); }
  // Scale mode (ADR 0014): the steps of an expected MIDI sequence, all given at once (at most kHmmMaxBias).
  void expect(const std::vector<int>& midi) {
    std::vector<int> a, b;
    for (size_t i = 1; i < midi.size(); ++i) {
      a.push_back(midi[i - 1]);
      b.push_back(midi[i]);
    }
    tr.set_bias(a.data(), b.data(), static_cast<int>(a.size()));
  }
};

}  // namespace

TEST(NoteTracker, SteadyNoteMeanStdAndTimes) {
  Driver d;
  for (int k = 0; k < 90; ++k) d.voiced((k % 2) ? 10.0 : -10.0);
  d.silent(21);
  ASSERT_EQ(d.notes.size(), 1u);
  const auto& n = d.notes[0];
  EXPECT_EQ(n.frames, 90);
  EXPECT_NEAR(n.t_start, 0.0, 1e-9);
  EXPECT_NEAR(n.t_end, 89 * kHop, 1e-9);
  EXPECT_NEAR(n.mean_c, 0.0, 0.3);
  EXPECT_NEAR(n.std_c, 10.0, 0.2);
  EXPECT_EQ(n.vib_rate, 0.0);
}

TEST(NoteTracker, ShortDropoutKeepsTheNoteAndLongGapEndsItAtOnce) {
  Driver d;
  d.run(100, 30);
  d.silent(20);  // exactly the limit: still the same note
  d.run(100, 30);
  d.silent(20);
  EXPECT_TRUE(d.notes.empty());
  d.silent(1);   // the 21st unvoiced frame closes it, without waiting for the HMM lag
  ASSERT_EQ(d.notes.size(), 1u);
  EXPECT_EQ(d.notes[0].frames, 60);
  EXPECT_EQ(d.emitted_at[0], d.i - 1);
}

TEST(NoteTracker, ASmearedStepSplitsAtItsSteepestPoint) {
  // 100 c step smeared over 4 frames (25, 50, 75, 100) as the 21 ms window does; frame 60 is the middle of the ramp.
  Driver d;
  d.run(0, 60);
  d.voiced(25); d.voiced(50); d.voiced(75);
  d.run(100, 60);
  d.silent(21);
  ASSERT_EQ(d.notes.size(), 2u);
  EXPECT_NEAR(d.notes[0].mean_c, 0.0, 0.01);
  EXPECT_NEAR(d.notes[1].mean_c, 100.0, 0.01);
  EXPECT_NEAR(d.notes[1].t_start / kHop, 61.0, 2.0);   // within ~2 frames (10 ms) of the middle of the ramp
}

TEST(NoteTracker, ANoteThatEndsInAStepIsReportedAboutOneLagLater) {
  Driver d;
  d.run(0, 80);
  d.run(100, 120);
  ASSERT_EQ(d.notes.size(), 1u);
  const int lag_frames = d.emitted_at[0] - 80;
  EXPECT_LE(lag_frames, intono::kHmmLag + 1);
  EXPECT_GE(lag_frames, intono::kHmmLag - 16);
  EXPECT_LE(lag_frames * kHop, 0.350);
}

TEST(NoteTracker, FlushDecodesTheLastFramesWhenARunEnds) {
  Driver d;
  d.run(0, 60);
  d.run(200, 30);   // the step is inside the last kHmmLag frames: only the flush can see it
  d.silent(21);
  ASSERT_EQ(d.notes.size(), 2u);
  EXPECT_EQ(d.notes[1].frames, 30);
}

TEST(NoteTracker, StepsUnderFiftyCentsAreOneNote) {
  Driver d;
  d.run(0, 60);
  d.run(40, 60);
  d.silent(21);
  EXPECT_EQ(d.notes.size(), 1u);
}

TEST(NoteTracker, SteadyWideVibratoAtAnyDetuningIsOneNote) {
  for (double centre : {-40.0, 0.0, 40.0, 60.0}) {
    for (double rate : {4.0, 5.5, 8.0}) {
      for (int ph = 0; ph < 8; ++ph) {
        Driver d;
        for (int k = 0; k < 280; ++k) d.voiced(centre + 50.0 * std::sin(2 * testutil::kPi * rate * k * kHop + ph * 0.785), false, rate, 100.0);
        d.silent(21);
        ASSERT_EQ(d.notes.size(), 1u) << "centre " << centre << " rate " << rate << " phase " << ph;
      }
    }
  }
}

// A note at the start or end of a run (a scale's tonic) is short: 16th notes at 120 bpm last 125 ms. Both edges must be
// separated from the long neighbour, with the boundary within 20 ms, for lengths of 100, 125 and 150 ms
// (ADR 0004 amendment, 2026-11-22).
namespace {
// edge note `edge_ms` long at `edge_c` next to a 600 ms note at `other_c`; `vib` cents of vibrato at 5.5 Hz on both.
std::vector<NoteSummary> edge_case(bool edge_first, double edge_ms, double edge_c, double other_c, double vib, double phase) {
  Driver d;
  const int ne = static_cast<int>(std::lround(edge_ms / 1000.0 / kHop)), nl = 112;
  auto seg = [&](double c, int n, int& k) {
    for (int q = 0; q < n; ++q, ++k) d.voiced(c + vib * std::sin(2 * testutil::kPi * 5.5 * k * kHop + phase), false, vib > 0 ? 5.5 : 0, 2 * vib);
  };
  int k = 0;
  if (edge_first) { seg(edge_c, ne, k); seg(other_c, nl, k); }
  else            { seg(other_c, nl, k); seg(edge_c, ne, k); }
  d.silent(21);
  return d.notes;
}
}  // namespace

TEST(NoteTracker, ShortNotesAtTheStartAndEndOfARunAreSeparated) {
  int bad = 0, total = 0;
  for (bool first : {true, false})
    for (double ms : {100.0, 125.0, 150.0})
      for (double step : {200.0, 100.0})
        for (double vib : {0.0, 30.0})
          for (int ph = 0; ph < 8; ++ph) {
            const auto n = edge_case(first, ms, first ? 0.0 : step, first ? step : 0.0, vib, ph * 0.785);
            ++total;
            const int ne = static_cast<int>(std::lround(ms / 1000.0 / kHop));
            const double truth = (first ? ne - 0.5 : 112 - 0.5) * kHop;   // the step lies between two frames
            const double err_ms = n.size() == 2u ? 1000.0 * std::fabs(n[1].t_start - truth) : 1e9;
            if (err_ms > 20.0) {
              ++bad;
              ADD_FAILURE() << (first ? "first" : "last") << " note " << ms << " ms, step " << step << " c, vibrato " << vib
                            << " phase " << ph << ": " << n.size() << " notes, boundary error " << err_ms << " ms";
            }
          }
  EXPECT_EQ(bad, 0) << bad << " of " << total;
}

TEST(NoteTracker, StrayPitchFramesAtTheEndOfARunDoNotMakeANote) {
  // As a note dies away YIN can return garbage for the last frames; the lowest HMM state then looks closest. That is not a
  // 16 ms note, and with the short-edge rule it must not become an 85 ms one either.
  for (double stray : {-2400.0, 1500.0, -900.0})
    for (int nstray : {1, 2, 3}) {
      Driver d;
      for (int k = 0; k < 110; ++k) d.voiced(30.0 + 45.0 * std::sin(2 * testutil::kPi * 4.3 * k * kHop), false, 4.3, 90.0);
      for (int k = 0; k < nstray; ++k) d.voiced(stray);
      d.silent(21);
      EXPECT_EQ(d.notes.size(), 1u) << "stray " << stray << " x" << nstray;
    }
}

TEST(NoteTracker, OctaveErrorFramesAtTheStartOfARunDoNotSplitOffANote) {
  // YIN often returns an octave error for the first few frames of a note (seen at 10 dB). The HMM starts in the
  // octave-down state and moves to the real one; the short-edge rule must not read that as a short first note.
  for (double err : {-1200.0, 1200.0, -1900.0})
    for (int nerr : {1, 2, 4, 5})
      for (double vib : {0.0, 25.0, 45.0}) {
        Driver d;
        for (int k = 0; k < nerr; ++k) d.voiced(err);
        for (int k = 0; k < 140; ++k) d.voiced(7.0 + vib * std::sin(2 * testutil::kPi * 5.2 * k * kHop), false, vib > 0 ? 5.2 : 0, 2 * vib);
        d.silent(21);
        EXPECT_EQ(d.notes.size(), 1u) << "error " << err << " x" << nerr << " vibrato " << vib;
      }
}

namespace {
// A run of consecutive legato notes (cents re A4), `ms[i]` long, centre `lv[i]`, `vib` cents of vibrato at 5.5 Hz on all of
// them; `glitch_at` >= 0 puts `nglitch` octave-error frames (-1200) at the head of that note. Returns the notes; the true
// boundaries (between two frames) are written to `truth`.
std::vector<NoteSummary> run_case(const std::vector<double>& ms, const std::vector<double>& lv, double vib, double phase,
                                  int glitch_at, int nglitch, std::vector<double>& truth, bool scale = false) {
  Driver d;
  if (scale) {   // the expected sequence is the played one (the nearest ET note of each level; levels are cents re A4 = MIDI 69)
    std::vector<int> m;
    for (double c : lv) m.push_back(69 + static_cast<int>(std::lround(c / 100.0)));
    d.expect(m);
  }
  int k = 0;
  truth.clear();
  for (size_t i = 0; i < ms.size(); ++i) {
    const int n = static_cast<int>(std::lround(ms[i] / 1000.0 / kHop));
    if (i) truth.push_back((k - 0.5) * kHop);
    for (int q = 0; q < n; ++q, ++k) {
      double c = lv[i] + vib * std::sin(2 * testutil::kPi * 5.5 * k * kHop + phase);
      if (static_cast<int>(i) == glitch_at && q < nglitch) c -= 1200.0;
      d.voiced(c, false, vib > 0 ? 5.5 : 0, 2 * vib);
    }
  }
  d.silent(21);
  return d.notes;
}
}  // namespace

TEST(NoteTracker, ShortNotesInTheMiddleOfARunAreNotMerged) {
  // ADR 0004 Amendment 4. Real clip #1: a scale of 140 ms notes lost its middle note, because the fit's window held two
  // boundaries. Runs of five notes, the three in the middle 100 to 170 ms, centre steps of 150 to 300 cents in both
  // directions, vibrato 0 and +-25 cents.
  int bad = 0, total = 0;
  const double durs[][3] = {{100, 100, 100}, {110, 125, 145}, {145, 140, 190}, {170, 130, 100}, {125, 170, 115}};
  const double steps[][4] = {{200, 200, 200, 200}, {-200, -300, -150, -200}, {200, -200, 300, -150}, {-150, 200, -200, 200}};
  for (const auto& dd : durs)
    for (const auto& st : steps)
      for (double vib : {0.0, 25.0})
        for (int ph = 0; ph < 4; ++ph) {
          std::vector<double> ms{300, dd[0], dd[1], dd[2], 300}, lv{0}, truth;
          for (int i = 0; i < 4; ++i) lv.push_back(lv.back() + st[i]);
          const auto n = run_case(ms, lv, vib, ph * 1.57, -1, 0, truth);
          ++total;
          double worst = 0;
          if (n.size() == 5u)
            for (size_t i = 1; i < 5; ++i) worst = std::max(worst, 1000.0 * std::fabs(n[i].t_start - truth[i - 1]));
          if (n.size() != 5u || worst > 25.0) {
            ++bad;
            ADD_FAILURE() << "durations " << dd[0] << "," << dd[1] << "," << dd[2] << " steps " << st[0] << "," << st[1] << ","
                          << st[2] << "," << st[3] << " vibrato " << vib << " phase " << ph << ": " << n.size()
                          << " notes, worst boundary error " << worst << " ms";
          }
        }
  EXPECT_EQ(bad, 0) << bad << " of " << total;
}

// ADR 0004 Amendment 4, condition set by Kelechi: a dwell under kFitMinEdge (12 frames, 64 ms) is treated as an octave-error
// glitch. A real note of 80 to 90 ms (15 to 17 frames) must not be taken for one, with and without octave-error frames at
// its head. Returns the number of failing cases (a missing note or a boundary more than 25 ms off).
static int mid_note_80_to_90(const std::vector<std::vector<double>>& step_sets, int* total, bool scale = false) {
  int bad = 0;
  *total = 0;
  for (double mid : {80.0, 85.0, 90.0})
    for (const auto& st : step_sets)
      for (double vib : {0.0, 25.0})
        for (int nerr : {0, 2})
          for (int ph = 0; ph < 3; ++ph) {
            std::vector<double> ms{300, 140, mid, 140, 300}, lv{0}, truth;
            for (int i = 0; i < 4; ++i) lv.push_back(lv.back() + st[i]);
            const auto n = run_case(ms, lv, vib, ph * 2.1, nerr ? 2 : -1, nerr, truth, scale);
            ++*total;
            double worst = 0;
            if (n.size() == 5u)
              for (size_t i = 1; i < 5; ++i) worst = std::max(worst, 1000.0 * std::fabs(n[i].t_start - truth[i - 1]));
            if (n.size() != 5u || worst > 25.0) {
              ++bad;
              ADD_FAILURE() << "middle note " << mid << " ms, steps " << st[0] << "," << st[1] << "," << st[2] << "," << st[3]
                            << " vibrato " << vib << " octave-error frames " << nerr << " phase " << ph << ": " << n.size()
                            << " notes, worst boundary error " << worst << " ms";
            }
          }
  return bad;
}

TEST(NoteTracker, ARealNoteOf80To90MsInsideAFastRunSurvivesTheGlitchRule) {
  int total = 0;
  const int bad = mid_note_80_to_90({{200, 200, 200, 200}, {200, -200, 300, -150}, {-150, 200, -200, 200}}, &total);
  EXPECT_EQ(bad, 0) << bad << " of " << total;
}

// Known limit of FREE mode, measured 2026-11-22 (ADR 0004, Amendment 4): with steps -200,-300,-150,-200 and vibrato of
// +-25 cents, 4 of 36 cases lose the 80 to 90 ms note (a 150-cent neighbour, a note below the 100 ms gate). Kept disabled as
// the record of that limit (ADR 0004, Amendment 5, Kelechi 2026-11-28): scale mode meets the requirement
// (ShortNoteNextToA150CentStepWithVibratoInScaleMode, 36/36). Run with --gtest_also_run_disabled_tests.
TEST(NoteTracker, DISABLED_ShortNoteNextToA150CentStepWithVibratoKnownLimit) {
  int total = 0;
  const int bad = mid_note_80_to_90({{-200, -300, -150, -200}}, &total);
  EXPECT_EQ(bad, 0) << bad << " of " << total;
}

// ADR 0014: the known limit above, in scale mode. The expected sequence is the played one, so the step into the short note is taken at
// kHmmSwitchExpected. The free-mode test stays disabled: free mode is unchanged by design.
TEST(NoteTracker, ShortNoteNextToA150CentStepWithVibratoInScaleMode) {
  int total = 0;
  const int bad = mid_note_80_to_90({{-200, -300, -150, -200}}, &total, true);
  EXPECT_EQ(bad, 0) << bad << " of " << total;
}

TEST(NoteTracker, ScaleModeKeepsEveryOtherFastRunCase) {
  int total = 0;
  const int bad = mid_note_80_to_90({{200, 200, 200, 200}, {200, -200, 300, -150}, {-150, 200, -200, 200}}, &total, true);
  EXPECT_EQ(bad, 0) << bad << " of " << total;
}

// ADR 0018: semitone steps of 60 to 80 cents in scale mode (notes played 20 to 40 cents flat or sharp, so neighbouring notes overlap the
// +-50 cent zones of the decoder's semitone states). Five legato notes 69 68 69 68 69 (a trill-like shape, the worst case: every step is
// narrow) at levels 8 -63 9 -62 10 cents re A4 (the 68s are 37 cents sharp, steps of 70 to 72 cents), middle notes 100 to 200 ms.
// Returns the number of cases (durations x vibrato phases) in which a note is missing, invented, or its boundary is more than 25 ms off.
static int narrow_trill(double vib, int* total, bool report) {
  int bad = 0;
  *total = 0;
  const double durs[][3] = {{140, 140, 140}, {100, 120, 100}, {200, 150, 200}, {120, 180, 110}};
  const std::vector<double> lv{8, -63, 9, -62, 10};
  for (const auto& dd : durs)
    for (int ph = 0; ph < 4; ++ph) {
      std::vector<double> ms{300, dd[0], dd[1], dd[2], 300}, truth;
      const auto n = run_case(ms, lv, vib, ph * 1.57, -1, 0, truth, true);
      ++*total;
      double worst = 0;
      if (n.size() == 5u)
        for (size_t i = 1; i < 5; ++i) worst = std::max(worst, 1000.0 * std::fabs(n[i].t_start - truth[i - 1]));
      if (n.size() != 5u || worst > 25.0) {
        ++bad;
        if (report) ADD_FAILURE() << "durations " << dd[0] << "," << dd[1] << "," << dd[2] << " vibrato " << vib << " phase " << ph << ": "
                      << n.size() << " notes, worst boundary error " << worst << " ms";
      }
    }
  return bad;
}

TEST(NoteTracker, ScaleModeSeparatesSemitoneNotesPlayed20To40CentsOff) {
  int total = 0;
  EXPECT_EQ(narrow_trill(0.0, &total, true), 0) << "without vibrato, " << total << " cases";
}

// With vibrato of +-12 cents on every note of the trill (phase-locked at 5.5 Hz, worst case) 7 of 16 cases still fail on 2026-11-28
// (12 of 16 with the old +-50 tolerance); the dev sets, with vibrato on half of the notes at random phases, measure the real rate. This pins the
// improvement; a lower count is welcome and the bound is lowered then.
TEST(NoteTracker, ScaleModeNarrowTrillWithVibratoStaysUnderTheMeasuredFailures) {
  int total = 0;
  const int bad = narrow_trill(12.0, &total, false);
  EXPECT_LE(bad, 7) << bad << " of " << total;
}

TEST(NoteTracker, ScaleModeDoesNotInventTheExpectedNoteWhenItIsNotPlayed) {
  // Expected A4 G4 E4; the player holds A4 and goes straight to E4 (skips G4), with and without vibrato and at several speeds.
  for (double vib : {0.0, 25.0})
    for (double mid_ms : {100.0, 150.0, 250.0}) {
      Driver d;
      d.expect({69, 67, 64});
      const int n1 = static_cast<int>(std::lround((300.0 + mid_ms) / 1000.0 / kHop)), n2 = static_cast<int>(std::lround(0.3 / kHop));
      for (int k = 0; k < n1; ++k) d.voiced(0 + vib * std::sin(2 * testutil::kPi * 5.5 * k * kHop), false, vib > 0 ? 5.5 : 0, 2 * vib);
      for (int k = 0; k < n2; ++k) d.voiced(-500 + vib * std::sin(2 * testutil::kPi * 5.5 * k * kHop), false, vib > 0 ? 5.5 : 0, 2 * vib);
      d.silent(21);
      ASSERT_EQ(d.notes.size(), 2u) << "vibrato " << vib << ", " << mid_ms << " ms";
      EXPECT_NEAR(d.notes[0].mean_c, 0, 30);
      EXPECT_NEAR(d.notes[1].mean_c, -500, 30);
    }
}

TEST(NoteTracker, NoBiasDecodesExactlyAsFreeMode) {
  const std::vector<double> ms{300, 120, 90, 140, 300}, lv{0, -200, -500, -650, -850};
  std::vector<double> t1, t2;
  const auto a = run_case(ms, lv, 25, 0.7, 2, 2, t1);
  Driver d;
  d.tr.set_bias(nullptr, nullptr, 0);
  int k = 0;
  for (size_t i = 0; i < ms.size(); ++i) {
    const int n = static_cast<int>(std::lround(ms[i] / 1000.0 / kHop));
    for (int q = 0; q < n; ++q, ++k) {
      double c = lv[i] + 25 * std::sin(2 * testutil::kPi * 5.5 * k * kHop + 0.7);
      if (static_cast<int>(i) == 2 && q < 2) c -= 1200.0;
      d.voiced(c, false, 5.5, 50);
    }
  }
  d.silent(21);
  ASSERT_EQ(a.size(), d.notes.size());
  for (size_t i = 0; i < a.size(); ++i) {
    EXPECT_EQ(a[i].t_start, d.notes[i].t_start);
    EXPECT_EQ(a[i].mean_c, d.notes[i].mean_c);
    EXPECT_EQ(a[i].frames, d.notes[i].frames);
  }
}

TEST(NoteTracker, OctaveErrorFramesInTheMiddleOfARunDoNotMakeOrHideANote) {
  // YIN returns an octave error for the first frames of a note at any point of a run. The path dwells in the octave-down
  // state for a few frames: that dwell is not a note, and it must not make the next switch look like a change in the wrong
  // direction (it hid the note after it before Amendment 4).
  int bad = 0, total = 0;
  for (int nerr : {1, 2, 3, 5})
    for (double vib : {0.0, 25.0})
      for (int ph = 0; ph < 3; ++ph) {
        std::vector<double> ms{300, 150, 150, 150, 300}, lv{0, -200, -500, -700, -1000}, truth;
        const auto n = run_case(ms, lv, vib, ph * 2.1, 3, nerr, truth);
        ++total;
        double worst = 0;
        if (n.size() == 5u)
          for (size_t i = 1; i < 5; ++i) worst = std::max(worst, 1000.0 * std::fabs(n[i].t_start - truth[i - 1]));
        if (n.size() != 5u || worst > 25.0) {
          ++bad;
          ADD_FAILURE() << nerr << " octave-error frames, vibrato " << vib << " phase " << ph << ": " << n.size()
                        << " notes, worst boundary error " << worst << " ms";
        }
      }
  EXPECT_EQ(bad, 0) << bad << " of " << total;
}

TEST(NoteTracker, ABriefOctaveDwellInsideASteadyNoteIsNotASplit) {
  for (int nerr : {1, 3, 6, 10})
    for (double vib : {0.0, 30.0}) {
      std::vector<double> truth;
      Driver d;
      for (int k = 0; k < 150; ++k) {
        double c = -300.0 + vib * std::sin(2 * testutil::kPi * 5.5 * k * kHop);
        if (k >= 70 && k < 70 + nerr) c += 1200.0;
        d.voiced(c, false, vib > 0 ? 5.5 : 0, 2 * vib);
      }
      d.silent(21);
      EXPECT_EQ(d.notes.size(), 1u) << nerr << " frames, vibrato " << vib;
    }
}

TEST(NoteTracker, AnRmsOnsetSplitsANoteOfTheSamePitch) {
  Driver d;
  d.run(0, 40);
  d.voiced(0, true);
  d.run(0, 40);
  d.silent(21);
  ASSERT_EQ(d.notes.size(), 2u);
  EXPECT_EQ(d.notes[0].frames, 40);
}

TEST(NoteTracker, ARunUnderTheMinimumLengthIsDiscarded) {
  Driver d;
  d.run(0, 9);
  d.silent(21);
  EXPECT_TRUE(d.notes.empty());
}

TEST(NoteTracker, VibratoFiguresNeedAtLeast30PercentOfTheFrames) {
  Driver a;
  for (int k = 0; k < 90; ++k) a.voiced(0, false, k >= 45 ? 5.5 : 0.0, k >= 45 ? 40.0 : 0.0);
  a.silent(21);
  ASSERT_EQ(a.notes.size(), 1u);
  EXPECT_NEAR(a.notes[0].vib_rate, 5.5, 1e-9);
  Driver b;
  for (int k = 0; k < 90; ++k) b.voiced(0, false, k >= 80 ? 5.5 : 0.0, k >= 80 ? 40.0 : 0.0);
  b.silent(21);
  ASSERT_EQ(b.notes.size(), 1u);
  EXPECT_EQ(b.notes[0].vib_rate, 0.0);
}

TEST(NoteSegmenter, RewindMovesFramesToTheNextNoteAndHeadTailAreTrimmed) {
  intono::NoteSegmenter seg(10);
  NoteSummary s;
  auto frame = [](int i, double c) { NoteFrame f; f.t = i * kHop; f.c = c; f.conf = 1; return f; };
  for (int i = 0; i < 30; ++i) seg.add(frame(i, 0));
  for (int i = 30; i < 36; ++i) seg.add(frame(i, 500));
  ASSERT_TRUE(seg.boundary(6, s, 30 * kHop));            // the six frames at 500 belong to the next note
  EXPECT_EQ(s.frames, 30);
  EXPECT_NEAR(s.mean_c, 0.0, 1e-9);
  EXPECT_NEAR(s.t_end, 29 * kHop, 1e-9);
  for (int i = 36; i < 50; ++i) seg.add(frame(i, 500));
  ASSERT_TRUE(seg.end(s));
  EXPECT_EQ(s.frames, 20);
  EXPECT_NEAR(s.t_start, 30 * kHop, 1e-9);
  EXPECT_NEAR(s.mean_c, 500.0, 1e-9);
}

// ---------------------------------------------------------------- engine level

namespace {

intono_config cfg48() {
  intono_config c{};
  c.sample_rate = 48000; c.window_size = 1024; c.hop_size = 256; c.a4_hz = 440; c.tuning = 0; c.min_hz = 180; c.max_hz = 3200;
  return c;
}

std::vector<intono_note> run_notes(const intono_config& c, const std::vector<float>& x, int chunk, int tonic = 60) {
  intono_engine* e = testutil::make_engine(&c);
  intono_set_tonic(e, tonic);
  std::vector<float> in = x;
  in.resize(in.size() + 6000, 0.f);  // lets the last note close
  std::vector<intono_note> all, buf(16);
  std::vector<intono_frame> fb(64);
  for (size_t p = 0; p < in.size(); p += chunk) {
    intono_process(e, in.data() + p, static_cast<int>(std::min<size_t>(chunk, in.size() - p)));
    while (intono_read_frames(e, fb.data(), 64) > 0) {}
    int n;
    while ((n = testutil::read_notes(e, buf.data(), 16)) > 0) all.insert(all.end(), buf.begin(), buf.begin() + n);
  }
  intono_destroy(e);
  return all;
}

}  // namespace

TEST(EngineNotes, ThreeNotePhraseWithLegatoStepAndBowGap) {
  // A4 +20 c, legato to B4 -15 c, a 150 ms gap, then C5 in tune. Detunings are what a scale grader must recover.
  std::vector<float> x(12000, 0.f);
  const auto a = testutil::harmonic(48000, 440.0 * std::exp2(20.0 / 1200), 0.5);
  const auto b = testutil::harmonic(48000, 440.0 * std::exp2((200.0 - 15.0) / 1200), 0.5);
  const auto c = testutil::harmonic(48000, 440.0 * std::exp2(300.0 / 1200), 0.5);
  x.insert(x.end(), a.begin(), a.end());
  x.insert(x.end(), b.begin(), b.end());
  x.insert(x.end(), 7200, 0.f);
  x.insert(x.end(), c.begin(), c.end());
  const auto notes = run_notes(cfg48(), x, 128);
  ASSERT_EQ(notes.size(), 3u);
  EXPECT_EQ(notes[0].midi_note, 69);
  EXPECT_EQ(notes[1].midi_note, 71);
  EXPECT_EQ(notes[2].midi_note, 72);
  EXPECT_NEAR(notes[0].mean_cents, 20.0, 2.0);
  EXPECT_NEAR(notes[1].mean_cents, -15.0, 2.0);
  EXPECT_NEAR(notes[2].mean_cents, 0.0, 2.0);
  for (const auto& n : notes) {
    EXPECT_LT(n.std_cents, 3.0);
    EXPECT_GT(n.mean_confidence, 0.9f);
    EXPECT_GT(n.frame_count, 60);
    EXPECT_EQ(n.vibrato_rate_hz, 0.f);
  }
  EXPECT_LT(notes[0].t_end, notes[1].t_start + 0.02);   // legato: the second note starts where the first ends
  EXPECT_GT(notes[1].t_start, 0.25 + 0.5 - 0.03);       // within ~30 ms of the true change at 0.75 s
  EXPECT_LT(notes[1].t_start, 0.25 + 0.5 + 0.03);
  EXPECT_GT(notes[2].t_start - notes[1].t_end, 0.1);    // the bow gap is outside both notes
  for (size_t i = 1; i < notes.size(); ++i) EXPECT_GE(notes[i].t_start, notes[i - 1].t_end);
}

// ADR 0018: in scale mode a note whose mean lies within 60 cents of a note that is due is that note, even when another semitone is nearer
// (a note 36 cents sharp with vibrato has a mean that wanders past the +-50 cent boundary). Free mode keeps the nearest target.
TEST(EngineNotes, ScaleModeLabelsANoteWithinSixtyCentsAsTheDueNote) {
  struct Case { double cents; int expect_free, expect_scale; double cents_scale; };
  const Case cases[] = {{55.0, 70, 69, 55.0}, {-58.0, 68, 69, -58.0}, {65.0, 70, 70, -35.0}, {20.0, 69, 69, 20.0}};
  for (const Case& cs : cases)
    for (bool scale : {false, true}) {
      const auto tone = testutil::harmonic(48000, 440.0 * std::exp2(cs.cents / 1200), 0.6);
      std::vector<float> x(9600, 0.f);
      x.insert(x.end(), tone.begin(), tone.end());
      x.resize(x.size() + 12000, 0.f);
      const intono_config conf = cfg48();
      intono_engine* e = testutil::make_engine(&conf);
      const int expected[2] = {69, 71};
      if (scale) intono_set_expected(e, expected, 2);
      std::vector<intono_note> all, buf(16);
      std::vector<intono_frame> fb(64);
      for (size_t p = 0; p < x.size(); p += 128) {
        intono_process(e, x.data() + p, static_cast<int>(std::min<size_t>(128, x.size() - p)));
        while (intono_read_frames(e, fb.data(), 64) > 0) {}
        int n;
        while ((n = testutil::read_notes(e, buf.data(), 16)) > 0) all.insert(all.end(), buf.begin(), buf.begin() + n);
      }
      intono_destroy(e);
      ASSERT_EQ(all.size(), 1u) << cs.cents << (scale ? " scale" : " free");
      EXPECT_EQ(all[0].midi_note, scale ? cs.expect_scale : cs.expect_free) << cs.cents << (scale ? " scale" : " free");
      if (scale) {
        EXPECT_NEAR(all[0].mean_cents, cs.cents_scale, 3.0) << cs.cents;
      }
    }
}

TEST(EngineNotes, VibratoNoteMeanIsTheCentreAndRateAndWidthAreReported) {
  const double sr = 48000, f_c = 440.0 * std::exp2(12.0 / 1200);  // A4 +12 c, vibrato +-30 c at 5.5 Hz
  std::vector<float> x(12000, 0.f);
  double ph = 0;
  for (size_t i = 0; i < static_cast<size_t>(sr * 1.5); ++i) {   // 8.25 whole vibrato cycles
    ph += 2 * testutil::kPi * f_c * std::exp2(30.0 * std::sin(2 * testutil::kPi * 5.5 * i / sr) / 1200) / sr;
    x.push_back(static_cast<float>(0.3 * std::sin(ph) + 0.15 * std::sin(2 * ph) + 0.1 * std::sin(3 * ph)));
  }
  const auto notes = run_notes(cfg48(), x, 256);
  ASSERT_EQ(notes.size(), 1u);
  EXPECT_NEAR(notes[0].mean_cents, 12.0, 3.0);
  EXPECT_NEAR(notes[0].vibrato_rate_hz, 5.5, 0.5);
  EXPECT_NEAR(notes[0].vibrato_width_cents, 60.0, 8.0);
  EXPECT_GT(notes[0].std_cents, 15.0);   // the raw pitch really swings; consumers tell vibrato from poor intonation by the width field
}

TEST(EngineNotes, JustIntonationTargetUsesTheTonic) {
  // C major, tonic C4: a major third in just intonation is 386.3 c, i.e. 13.7 c below ET. Play it ET-perfect.
  intono_config c = cfg48();
  c.tuning = 1;
  std::vector<float> x(12000, 0.f);
  const auto e4 = testutil::harmonic(48000, 440.0 * std::exp2(-500.0 / 1200), 0.6);  // E4 in ET
  x.insert(x.end(), e4.begin(), e4.end());
  const auto notes = run_notes(c, x, 128, 60);
  ASSERT_EQ(notes.size(), 1u);
  EXPECT_EQ(notes[0].midi_note, 64);
  EXPECT_NEAR(notes[0].mean_cents, 13.7, 2.0);   // sharp of the just third
}

TEST(EngineNotes, ResultsDoNotDependOnChunking) {
  std::vector<float> x(12000, 0.f);
  const auto a = testutil::harmonic(48000, 440.0, 0.4);
  const auto b = testutil::harmonic(48000, 440.0 * std::exp2(300.0 / 1200), 0.4);
  x.insert(x.end(), a.begin(), a.end());
  x.insert(x.end(), b.begin(), b.end());
  const auto n1 = run_notes(cfg48(), x, 1), n2 = run_notes(cfg48(), x, 997);
  ASSERT_EQ(n1.size(), n2.size());
  for (size_t i = 0; i < n1.size(); ++i) {
    EXPECT_EQ(n1[i].frame_count, n2[i].frame_count);
    EXPECT_EQ(n1[i].mean_cents, n2[i].mean_cents);
  }
}

TEST(EngineNotes, ArgumentChecksAndRingNeverBlocks) {
  intono_note buf[4];
  EXPECT_EQ(testutil::read_notes(nullptr, buf, 4), 0);
  const intono_config c = cfg48();
  intono_engine* e = testutil::make_engine(&c);
  EXPECT_EQ(testutil::read_notes(e, nullptr, 4), 0);
  EXPECT_EQ(testutil::read_notes(e, buf, 0), 0);
  EXPECT_EQ(testutil::read_notes(e, buf, 4), 0);
  // 150 short notes with nobody reading: the 64-entry ring drops the newest, processing carries on
  std::vector<float> x(12000, 0.f);
  const auto n = testutil::harmonic(48000, 440.0, 0.1);
  for (int i = 0; i < 150; ++i) {
    x.insert(x.end(), n.begin(), n.end());
    x.insert(x.end(), 7200, 0.f);
  }
  // This test feeds ~6 s of audio far faster than real time. Threaded, a slow worker (a shared macOS VM) would overflow the 1024-hop
  // record queue and drop hops, which is a different thing from the 64-entry note ring this test is about. So wait for the worker after
  // every chunk (drain is a no-op in inline mode); the note ring is still never read and still has to drop the newest.
  for (size_t p = 0; p < x.size(); p += 512) {
    intono_process(e, x.data() + p, static_cast<int>(std::min<size_t>(512, x.size() - p)));
    intono_internal::drain(e);
  }
  int total = 0, got;
  while ((got = testutil::read_notes(e, buf, 4)) > 0) total += got;
  EXPECT_EQ(total, 64);
  intono_destroy(e);
}

TEST(EngineNotes, LegatoStepsOfAnySizeOverFiftyCentsSplitTheNote) {
  // The 21 ms window smears an abrupt step over ~3 frames, so a small step arrives in pieces under the 30 c
  // frame-to-frame jump rule. Every step from 60 c up must still give two notes, in both directions.
  for (double step : {60.0, 75.0, 100.0, 150.0, -60.0, -75.0, -100.0, -150.0}) {
    std::vector<float> x(12000, 0.f);
    const auto a = testutil::harmonic(48000, 440.0, 0.5);
    const auto b = testutil::harmonic(48000, 440.0 * std::exp2(step / 1200), 0.5);
    x.insert(x.end(), a.begin(), a.end());
    x.insert(x.end(), b.begin(), b.end());
    const auto notes = run_notes(cfg48(), x, 128);
    ASSERT_EQ(notes.size(), 2u) << "step " << step;
    EXPECT_NEAR(notes[1].t_start, 0.75, 0.04) << "step " << step;
    EXPECT_NEAR(notes[0].mean_cents, 0.0, 1.5) << "step " << step;                 // the ramp is not in the old note's mean
    EXPECT_NEAR(notes[1].mean_cents + 100.0 * (notes[1].midi_note - 69), step, 1.5) << "step " << step;
  }
}

TEST(EngineNotes, StepsUnderFiftyCentsAreNotSplitAndVibratoIsNotAStep) {
  std::vector<float> x(12000, 0.f);
  const auto a = testutil::harmonic(48000, 440.0, 0.5);
  const auto b = testutil::harmonic(48000, 440.0 * std::exp2(40.0 / 1200), 0.5);  // 40 c: a different pitch, not a different note
  x.insert(x.end(), a.begin(), a.end());
  x.insert(x.end(), b.begin(), b.end());
  EXPECT_EQ(run_notes(cfg48(), x, 128).size(), 1u);
}

// ------------------------------------------------------------------------------------------------------------
// ADR 0004: legato step under wide vibrato. Note A is a semitone-0 note 40 c sharp, note B a semitone higher and in
// tune, so the intended pitches differ by 60 c. Both carry +-50 c vibrato at 6 Hz; the vibrato phase at the step is swept.
namespace {
struct Emitted { intono_note n; double at; };

std::vector<Emitted> run_notes_timed(const std::vector<float>& x) {
  const intono_config c = cfg48();
  intono_engine* e = testutil::make_engine(&c);
  std::vector<float> in = x;
  in.resize(in.size() + 6000, 0.f);
  std::vector<Emitted> all;
  intono_note buf[8];
  std::vector<intono_frame> fb(64);
  for (size_t p = 0; p < in.size(); p += 128) {
    const size_t n = std::min<size_t>(128, in.size() - p);
    intono_process(e, in.data() + p, static_cast<int>(n));
    while (intono_read_frames(e, fb.data(), 64) > 0) {}
    int got;
    while ((got = testutil::read_notes(e, buf, 8)) > 0)
      for (int i = 0; i < got; ++i) all.push_back({buf[i], static_cast<double>(p + n) / 48000.0});
  }
  intono_destroy(e);
  return all;
}

std::vector<float> vibrato_tone(double centre_c, double amp_c, double rate, double phase0, double secs, double* ph_acc) {
  std::vector<float> x(static_cast<size_t>(48000 * secs));
  for (size_t i = 0; i < x.size(); ++i) {
    const double cents = centre_c + amp_c * std::sin(2 * testutil::kPi * rate * i / 48000.0 + phase0);
    *ph_acc += 2 * testutil::kPi * 440.0 * std::exp2(cents / 1200.0) / 48000.0;
    x[i] = static_cast<float>(0.3 * std::sin(*ph_acc) + 0.15 * std::sin(2 * *ph_acc) + 0.1 * std::sin(3 * *ph_acc));
  }
  return x;
}
}  // namespace

TEST(EngineNotes, LegatoStepOf60CentsUnderWideVibratoSplitsWithinTwentyMsAndWithinTheDelayBudget) {
  const double t_step = 0.25 + 0.9;
  int n_cases = 0, n_within_20ms = 0;
  double worst_s = 0.0;
  for (int pa = 0; pa < 8; ++pa) {          // vibrato phase of note A at the step
    for (int pb = 0; pb < 8; pb += 3) {     // vibrato phase of note B at the step
      const double phA = 2 * testutil::kPi * pa / 8, phB = 2 * testutil::kPi * pb / 8, rate = 6.0;
      double ph = 0;
      std::vector<float> x(12000, 0.f);
      const auto a = vibrato_tone(40.0, 50.0, rate, phA - 2 * testutil::kPi * rate * 0.9, 0.9, &ph);
      const auto b = vibrato_tone(100.0, 50.0, rate, phB, 0.9, &ph);
      x.insert(x.end(), a.begin(), a.end());
      x.insert(x.end(), b.begin(), b.end());
      const auto notes = run_notes_timed(x);
      const std::string tag = "phase A " + std::to_string(pa) + " B " + std::to_string(pb);
      ASSERT_EQ(notes.size(), 2u) << tag;
      EXPECT_EQ(notes[0].n.midi_note, 69) << tag;
      EXPECT_EQ(notes[1].n.midi_note, 70) << tag;
      EXPECT_NEAR(notes[1].n.t_start, t_step, 0.100) << tag;   // ADR 0004 gate: max 100 ms ...
      EXPECT_LE(notes[0].at - t_step, 0.350) << tag;
      ++n_cases;
      n_within_20ms += std::fabs(notes[1].n.t_start - t_step) <= 0.020;
      worst_s = std::max(worst_s, std::fabs(notes[1].n.t_start - t_step));
    }
  }
  // Every case here has +-50 cent vibrato on both notes at 6 Hz, the hardest mix of the generator, so it is harsher
  // than the dev/gate sets (p95 14 ms there). Measured: 18 of 24 within 20 ms. The p95 gate lives in run_boundaries.py.
  RecordProperty("worst_boundary_error_ms", static_cast<int>(1000.0 * worst_s));
  EXPECT_GE(n_within_20ms, 0.7 * n_cases);
  std::printf("legato sweep: %d of %d boundaries within 20 ms, worst %.1f ms\n", n_within_20ms, n_cases, 1000.0 * worst_s);
}

TEST(EngineNotes, SteadyWideVibratoIsNeverSplit) {
  for (double centre : {-40.0, 0.0, 40.0}) {
    for (int pa = 0; pa < 8; ++pa) {
      double ph = 0;
      std::vector<float> x(12000, 0.f);
      const auto a = vibrato_tone(centre, 50.0, 6.5, 2 * testutil::kPi * pa / 8, 1.6, &ph);
      x.insert(x.end(), a.begin(), a.end());
      ASSERT_EQ(run_notes_timed(x).size(), 1u) << "centre " << centre << " phase " << pa;
    }
  }
}
