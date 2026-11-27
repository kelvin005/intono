# Phase 3 plan: scale mode

Phase 3 is scale mode for v1 (ADR 0011), within the v1 scope of ADR 0012: no accounts, no backend, one-time Pro unlock. Related ADRs:
replay in RAM (ADR 0013), score-informed segmentation (ADR 0014, with Amendment 1), the local practice database (ADR 0015).
Architecture: `docs/architecture.md`; its Backend, Sync, remote-config and subscription sections are outdated for v1 (ADR 0012).

## Status (2026-11-27)

| Item | State |
|---|---|
| 1. Scale definitions as data | **merged** (#26) |
| 2. Scale grader | **merged** (#30). Min note 80 ms; score (🟢 + 0.5·🟡)/n |
| 3. Score-informed segmentation (hard gate) | **merged** (#34). Sealed **p3gate passed** (G-P3 1.0000) and **p3dev passed** (0 of 1024 invented, recall 1.0000), one run each (#36, #38) |
| 4. Scale screen | **merged** (#33) |
| 5. Finger/string results stored locally (drift) | **in progress**: ADR 0015 accepted (#35); implementation next |
| Replay of own audio (RAM, 60 s) | ADR 0013 accepted; implemented with the review screen, after item 5 |

## Open before Phase 3 closes

Phase 3 closes only when both of these are done, as the p3gate pre-registration requires ("Also required").

### A. The free-mode known-limit test (ADR 0004)

- **Test:** `DISABLED_ShortNoteNextToA150CentStepWithVibratoKnownLimit` in `dsp/tests/test_notes.cpp`.
- **Today:** it still fails in free mode, as designed. Scale mode solves the same case: `ShortNoteNextToA150CentStepWithVibratoInScaleMode`,
  36 of 36.
- **Done means:** the test is enabled and passes, or Kelechi re-scopes the requirement and that is recorded in ADR 0004.
- **Decision needed (Kelechi):** which of these?
  - **(a) Fix free mode.** Make free mode pass the case. Under the DSP freeze this needs a real-audio result or a CI failure that
    motivates it, an ADR, and golden free-mode identity would end by design, so it needs a new golden tag.
  - **(b) Re-scope the requirement.** Accept the scale-mode test as meeting it, and keep the free-mode test disabled as a documented
    limit of free mode, which has no score to lean on.

### B. Revisit the ADR 0004 glitch rule after ADR 0007

- **The rule:** short off-pitch runs are folded into the surrounding note. ADR 0007 (octave errors on weak fundamentals) changed what the
  tracker sees, so the rule's thresholds were tuned on inputs that no longer occur.
- **Done means:**
  - The rule is re-measured on dev seeds with the current tracker, in free mode and in scale mode.
  - It is kept or changed, with the result recorded in ADR 0004.
  - Any change follows the DSP freeze (an ADR, motivated by a real-audio result or a CI failure) and passes the golden check, or comes
    with a new golden tag if it changes free mode.
  - Gate results are re-checked on dev seeds; the spent sealed sets are never re-run.

## Decisions (Kelechi)

- **Thresholds** (bundled `app/assets/config/grading.json`): green 5¢, yellow 15¢, min note 80 ms, merge gap 120 ms, merge pitch
  tolerance 25¢.
- **Score:** % = (🟢 + 0.5·🟡) / expected notes; the counts are shown next to the %.
- **Fingering:** open strings by default; 4th-finger variants later.
- **Replay:** the student's own audio in RAM only, the last 60 s, discarded on leaving review; never written to disk, never uploaded.
- **ADR 0012:**
  - no accounts, backend or sync;
  - one-time Pro unlock;
  - Phase 4 is "Pro unlock and store readiness";
  - the practice DB is in Android Auto Backup and iCloud backup;
  - no crash SDK.
- **ADR 0014:**
  - one skipped note allowed;
  - after 3 misses, plain segmentation until 2 notes match again;
  - a separate sealed gate for invented notes (≤ 0.5 %, recall ≥ 0.98);
  - Amendment 1 (cheap entry into the due note from any state).
- **ADR 0015:**
  - drop `device_id` and the sync fields;
  - keep `instrument` (default `violin`);
  - store every graded note, with the totals as a cache;
  - keep sessions forever, with "Clear history" in settings.

## Hard gate (met)

Kelechi, 2026-11-22: recall ≥ 0.995 on 100 to 250 ms notes whose smaller adjacent step is 100 to 150 cents, on the sealed set p3gate
(seeds 34201–34216). It was measured on 2026-11-27 at 1.0000 (1087 notes). See `tools/accuracy/reports/phase3/sealed_p3.md`.

Deferred by Kelechi: the scale grader merges same-pitch splits.
