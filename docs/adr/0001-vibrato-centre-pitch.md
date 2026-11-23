# ADR 0001: Vibrato centre pitch uses peak/trough midpoints

Status: Accepted (Kelechi, 2026-11-21). Amended 2026-11-21: note-change reset (item 7) and known limit.

## Context

The architecture doc defines the displayed pitch as the "median over one vibrato cycle" and detects vibrato (4 to 8 Hz) on a 250 ms contour. A 4 Hz vibrato has a 250 ms period, so an autocorrelation over a 250 ms contour cannot see even one full period. In the Phase 0 reference (`tools/accuracy/ref`), this gave a vibrato-centre error of 5.75 cents, which misses the under-5-cent target.

## Options measured (Phase 0 synthetic set, 136 clips, 16 vibrato clips at 4 to 8 Hz and 10 to 80 cents peak-to-peak)

| Option | Vibrato-centre MAE | Lag | Notes |
|---|---|---|---|
| A. Autocorrelation, 250 ms (doc as written) | 5.75 c | none | misses target |
| B. Autocorrelation, 500 ms | 1.31 c | +250 ms | too slow for the 50 ms latency budget |
| C. Peak/trough midpoint, no safeguards | 0.68 c | none | noise bumps can become false peaks |
| **D. Peak/trough midpoint with safeguards (chosen)** | **0.65 c** (1.03 c at 10 dB SNR) | none | 0% false vibrato on non-vibrato clips |

## Decision

Live display uses option D, on the existing 250 ms contour:

1. Smooth the contour with a 3-frame mean (about 16 ms).
2. An extremum only counts when the contour swings at least 8 cents away from it (`vib_min_swing_c`).
3. Vibrato is declared when the last two extrema are 10 to 100 cents apart and imply a 3.5 to 9 Hz rate.
4. Centre pitch is the mean of the midpoints of consecutive extrema over the last full cycle (up to the last 4 extrema).
5. Hold-over: because step 2 confirms an extremum only after the contour has swung back, the latest extremum arrives late. Once vibrato is established, the previous centre is held for up to one contour length (250 ms). Without the hold-over, 15 to 25% of vibrato frames fell back to the median and the error rose to 1.86 c.
6. No vibrato found: median over the last 150 ms (as in the doc).
7. Note-change reset: a jump of more than 30 cents between consecutive frames starts a new note. The contour, the hold-over and the vibrato outputs are cleared, so the first frames of the new note show the new pitch and never a stale centre. Steady playing cannot trigger it: the steepest allowed vibrato (8 Hz, 100 c peak to peak) moves about 13 c per 5.3 ms frame. A voicing gap (silence or a failed frame) also starts a new note, as before.

Scale grading does not use the live value. It scores each note after it ends, with no latency constraint, so it uses the mean pitch over the whole note (in cents, then converted back).

## Consequences

- The vibrato outputs (rate, width) come from the same extrema, so they need no separate detector.
- The C++ core must reproduce this behaviour; the accuracy harness compares it against `yin_ref.py` (`centre_method="extrema"`).
- All parameters (8 c swing, 3.5 to 9 Hz, hold length) are config values so field data can tune them.
- Not yet validated on real violin recordings; the synthetic set has clean periodic vibrato. Re-check on URMP once available, in particular the false-vibrato rate on real stable notes.
- Known limit: at 4 Hz a vibrato fills the whole 250 ms contour, so a narrow one (about 12 c) often has fewer than two confirmed extrema and falls back to the 150 ms median. Worst frame error there is about 3.5 c (inside the 5 c target) and vibrato rate and width may read 0. A longer contour would fix it at the cost of lag; revisit with field data.
- Tests: `CentreTracker.JumpToSteadyNoteAfterVibratoShowsNoStaleCentre` and `...JumpToNewVibratoNoteConverges...` try jumps of +60, +100, -80, +300 and -700 cents at every phase of the vibrato cycle, so they land both on confirmed centres and during hold-over. Without item 7 the first frame after the jump showed the old centre, 100 c wrong.
- The architecture doc's "Smoothing and vibrato" bullet matches this ADR (updated by Kelechi).
