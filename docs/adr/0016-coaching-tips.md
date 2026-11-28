# ADR 0016: Coaching tips in words (Phase 3)

Status: **Proposed** (2026-11-28). The rules and thresholds are new decisions, so this needs Kelechi's "merge". The questions are at
the end.

## Context

The architecture doc ("Coaching") asks for these after each run:
- at most one or two short tips, chosen by rules: the most consistent error first, then a suggested exercise;
- fixed templates with filled-in values, not free-form AI text, so they are predictable and testable;
- thresholds for "often" and "sharp" kept outside the code.

ADR 0011 (answer 1) and ADR 0012 rule out remote config in v1, so the thresholds are a bundled file. The data is the finger-level history
(`graded_notes`, the last 30 days, ADR 0015), which includes the run just finished.

## Decision (proposed)

1. **Thresholds** live in `app/assets/config/coaching.json` (format 1). They are bundled; change them with a release.

   | Key | Value | Meaning |
   |---|---|---|
   | `min_notes` | 4 | Played notes on one (string, finger, placement) before it can get a tip |
   | `sharp_cents` | 10 | The average error must be at least this |
   | `often_fraction` | 0.6 | At least this share of those notes is off in the same direction by more than the green threshold (5¢) |
   | `missed_tip_min` | 2 | Missed notes in the run before the "not heard" tip |
   | `max_tips` | 2 | Tips per run |

2. **Rules, in order.** The first `max_tips` that apply are shown:
   1. **Habitual finger errors.** These are the (string, finger, placement) cells that pass all three thresholds, most consistent
      first: the highest same-direction share, then the larger average.
      - The first one gets an exercise:
        - "Your high 3rd finger on A is often 15¢ sharp. Play E harmonic minor, 1 octave slowly with the drone."
        - The exercise is the run's own scale if it uses that finger ("Play G major, 1 octave again slowly with the drone").
          Otherwise it is the bundled scale with the most notes on that finger, ties to the shorter scale, then library order.
        - An open string is a tuning matter, so it gets: "Your open D string is often 8¢ flat. Tune it against the drone before
          you play."
      - Further ones: "Your 1st finger on E is often 12¢ flat too."
   2. **Missed notes.** If the run missed at least `missed_tip_min` notes: "3 notes were not heard. Play slower, with one clear bow
      per note."
   3. **Nothing to fix.** If no other rule applied: "No habitual error yet. Play it again with the drone to keep it that way."
3. Tips are shown on the review screen under the counts. They are computed after the run has been saved, so the history includes
   it. Without a history (the database failed to open), the run alone is used.
4. **Tests first:** each rule, each threshold at its edge, the ordering, the tip limit, the exercise choice, open strings, and
   config validation.

## Questions for Kelechi

1. Are the values right (4 notes, 10¢, 60 %, 2 missed, 2 tips)? A teacher's view would help; they are easy to change.
2. Exercise choice: is "the run's own scale if it uses that finger, else the scale with the most notes on it" right, or should it
   always suggest a 1-octave scale?
3. Wording: is the English of the five templates right for students?

## Status note 2026-11-28: only trustworthy notes

Tips and the heatmap use only notes graded within the label window (`label_window_cents`, 60): 🟢/🟡/🔴 by cents. Missed, wrong, extra
and out-of-window notes never make a "habit" (the "often 27¢ sharp" tip of phone test 1 came from a +1029¢ note stored as a 🔴).
The missed-notes tip counts only notes not heard at all; a wrong note is not "not heard". Runs that were not heard, or that the player
did not save, are not in the history at all (ADR 0011 status note of the same date). Thresholds unchanged (4 notes, 10¢, 60%, 2, 2).
