# Score-informed segmentation (ADR 0014): dev-seed results

Dev seeds only: short runs 9501 to 9516 (`run_short_runs.py --min-step 100 --scale`, 16 x 30 phrases, the p3gate generator) and
deviations 9521 to 9536 (`run_deviations.py`, 16 x 64 phrases, 1024 deviations, the p3dev generator). The sealed sets p3gate
(34201-34216) and p3dev (34301-34316) have not been generated or run. Build: `phase3/score-informed`, `intono-cli` Release, Linux x86-64.

## Free mode vs scale mode, same short-run dev seeds (2867 notes)

| | Free mode | Scale mode (final) |
|---|---|---|
| Notes found | 2770 (0.9662) | **2865 (0.9993)** |
| Missed | 97 | **2** |
| Extra notes per 200 | 2.72 | **0.14** |

Free mode is byte-identical to `phase1-complete` (golden manifest, 288 comparisons, inline and threaded: 0 differ).

## Final parameter: entry rule (ADR 0014 Amendment 1), `kHmmSwitchExpected` = 8

| Gate (as pre-registered) | Limit | Dev result |
|---|---|---|
| G-P3: recall, 100-250 ms notes, smaller step 100-150 cents | >= 0.995 | **0.9981** (1043 notes, 2 missed) |
| recall, step >= 150 cents, notes >= 150 ms | >= 0.995 | 1.0000 (1232 notes) |
| recall, step >= 150 cents, notes 100-150 ms | >= 0.98 | 1.0000 (275 notes) |
| extra notes per 200 truth notes | <= 1 | 0.14 |
| p3dev: invented-expected-note rate | <= 0.5 % | **0.0 %** (0 of 1024) |
| p3dev: recall of the played deviation notes | >= 0.98 | **0.9987** (767 of 768) |

By deviation kind (256 each): wrong 0 invented, 255 of 256 found; skip 0 invented; repeat 0 invented, 256 found; off-scale 0 invented,
256 found. The two G-P3 misses: seed 9507, MIDI 71, 111 ms at a 100 cent step; seed 9511, MIDI 75, 100 ms at a 101 cent step.

## The sweep (how 8 was chosen)

Step rule (decision 3 as accepted: cheap only from `expected[k-1]`):

| Cost | G-P3 | invented | deviation recall |
|---|---|---|---|
| 8 | 0.9981 | 8 (all off-scale) | 0.9779 |
| 12 | 0.9952 | 3 | 0.9909 |
| 16 | 0.9923 | 2 | 0.9948 |
| 20 | 0.9837 | 0 | 0.9974 |

Entry rule (Amendment 1: cheap entry into the due note from any state):

| Cost | G-P3 | invented | deviation recall | extra per 200 |
|---|---|---|---|---|
| 4 | 0.9981 | 0 | 0.9987 | 0.14 |
| 6 | 0.9981 | 0 | 0.9987 | 0.14 |
| 8 | 0.9981 | 0 | 0.9987 | 0.14 |
| 12 | 0.9952 | 0 | 0.9987 | 0.07 |
| 16 | 0.9847 | 0 | 0.9987 | 0.35 |

8 is the weakest bias on the 4-8 plateau. Normal switch cost (`kHmmSwitch`) is 24.

## Other checks

- Unit tests: 103 pass inline and threaded (12 cursor tests, 4 tracker scale-mode tests, 5 engine scale-mode tests).
- Real-time safety: `RtSafety.ScaleModeNeverAllocatesOrLocks` and `...WithWorker` pass (the sequence is also re-set inside the armed
  region).
- ThreadSanitizer: the threaded scale-mode and worker tests run clean (no reports).

## Still open before the sealed runs

The addendum to `docs/adr/sealed-p3gate-preregistration.md`: the frozen binary's path and sha256 and the hashes of `run_short_runs.py`,
`run_deviations.py`, `notes_hmm.hpp` and `intono.h`, written after this PR merges and built from the merge commit. Then each sealed set runs
once. Outside this work: `DISABLED_ShortNoteNextToA150CentStepWithVibratoKnownLimit` still fails in free mode, as designed (scale mode
passes its case: `ShortNoteNextToA150CentStepWithVibratoInScaleMode`, 36/36).
