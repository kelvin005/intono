# Sealed runs p3gate and p3dev (ADR 0014): reported as measured

Run once each on 2026-11-27, from `main` at `9322515`, after the frozen-binary addendum merged (#36).

- **Binary:** the frozen `/home/claude/frozen/intono-cli-fc29130`, built from `fc29130`. Its sha256,
  9e77f56f1519f40c126c4b9a9ccd61a1f6ad7ca85f1f188a2688c5599d7d00f7, was re-checked right before the runs.
- **Runners:** `run_short_runs.py` and `run_deviations.py` on `main` had the sha256s that the addendum records.
- Nothing was tuned or re-run. The log lines are in `reports/phase1/short_run_runs.log` (p3gate) and
  `reports/phase3/deviation_runs.log` (p3dev).

## p3gate: seeds 34201 to 34216, scale mode, 2910 truth notes

| Gate | Limit | Measured | |
|---|---|---|---|
| **G-P3:** recall, 100 to 250 ms notes, smaller adjacent step 100 to 150 cents | >= 0.995 | **1.0000** (1087 notes, 0 missed) | PASS |
| Recall, step >= 150 cents, notes >= 150 ms | >= 0.995 | 1.0000 (1211 notes) | PASS |
| Recall, step >= 150 cents, notes 100 to 150 ms | >= 0.98 | 0.9968 (309 notes, 1 missed) | PASS |
| Extra notes per 200 truth notes | <= 1 | 0.07 (1 extra) | PASS |

Overall: 2909 of 2910 notes recovered.

## p3dev: seeds 34301 to 34316, 1024 deviations

| Gate | Limit | Measured | |
|---|---|---|---|
| Invented-expected-note rate | <= 0.5 % | **0.0 %** (0 of 1024) | PASS |
| Recall of the played deviation notes | >= 0.98 | **1.0000** (768 of 768) | PASS |

By kind, 256 each:

| Kind | Invented | Played notes found |
|---|---|---|
| wrong | 0 | 256 of 256 |
| skip | 0 | — (nothing is played) |
| repeat | 0 | 256 of 256 |
| off-scale | 0 | 256 of 256 |

## Compared with the dev seeds

The sealed results are as good as or better than the dev results (`score_informed_dev.md`):

| | Dev | Sealed |
|---|---|---|
| G-P3 | 0.9981 | 1.0000 |
| Deviation recall | 0.9987 | 1.0000 |
| Invented | 0 | 0 |

The dev misses were at the corner of the band, notes of 100 to 111 ms at a step of 100 to 101 cents. This sealed set had none there
that failed.

## Notes

- **Reproducibility.** The clips were generated on this workspace's x86-64 machine, which has AVX-512, with numpy 2.5.3 and scipy
  1.18.1. numpy's AVX-512 kernels make slightly different noisy clips than its baseline kernels (found on #34, fixed for the golden
  manifest in #37). The sealed runners themselves are frozen by the addendum hashes and do not pin numpy's kernels, so a
  re-generation on a CPU without AVX-512 may give slightly different noisy clips. The sets are spent either way.
- **Still required before Phase 3 closes** (pre-registration, "Also required"):
  - Free mode byte-identical to today: holds.
  - `DISABLED_ShortNoteNextToA150CentStepWithVibratoKnownLimit`: still fails in free mode. Its case passes in scale mode, in
    `ShortNoteNextToA150CentStepWithVibratoInScaleMode`.
  - The ADR 0004 glitch rule, revisited after ADR 0007: open.
