# Phase 3 plan: scale mode

Phase 3 is scale mode for v1 (ADR 0011), within the v1 scope of ADR 0012: no accounts, no backend, one-time Pro unlock. Related ADRs:
replay in RAM (ADR 0013), score-informed segmentation (ADR 0014, with Amendment 1), the local practice database (ADR 0015).
Architecture: `docs/architecture.md`; its Backend, Sync, remote-config and subscription sections are outdated for v1 (ADR 0012).

## Status (2026-11-28)

| Item | State |
|---|---|
| 1. Scale definitions as data | **merged** (#26) |
| 2. Scale grader | **merged** (#30). Min note 80 ms; score (🟢 + 0.5·🟡)/n |
| 3. Score-informed segmentation (hard gate) | **merged** (#34). Sealed **p3gate passed** (G-P3 1.0000) and **p3dev passed** (0 of 1024 invented, recall 1.0000), one run each (#36, #38) |
| 4. Scale screen | **merged** (#33) |
| 5. Finger/string results stored locally (drift) | **merged** (#41): every graded note, the totals as caches, Clear history, the database in Android/iOS backup. On-device test on the emulator and the Simulator. SQLite pinned by version and hash (#43, ADR 0015 Note 1) |
| iOS: microphone off during review | **#46**: an output-only engine for the review. **Required before TestFlight** (Kelechi, 2026-11-28) |
| Sealed set for 60 to 80 cent steps (semitones 20 to 40¢ off), recall ≥ 0.99, invented ≤ 0.5 % | **Not registered.** On dev seeds the current engine gets 0.891 and 1.93 % (`tools/accuracy/reports/phase3/semitone_dev.md`); passing needs a scale-mode decoder change under the DSP freeze. **Waiting on Kelechi's decision** |
| Finger/string heatmap screen (from `graded_notes`, last 30 days) | **#47** |
| Coaching tips in words (rule-based templates) | next |
| Spoken summary after a run (on-device TTS, microphone paused) | after the tips |
| App uses scale mode | **merged** (#40): the scale screen gives the engine the expected sequence |
| Replay of own audio (RAM, 60 s) | **merged** (#45): tap a note or "Play the run" on the review screen. Zeroed and released on leaving, Play again, background, close. Android stops the microphone during review. **Needs Kelechi's phone check** |
| iOS: microphone off during review | **#46**: an output-only engine for the review. **Required before TestFlight** (Kelechi, 2026-11-28) |

## Open before Phase 3 closes

Phase 3 closes only when both of these are done, as the p3gate pre-registration requires ("Also required").

### A. The free-mode known-limit test (ADR 0004): **done** (Kelechi, 2026-11-28)

- **Decision:** the scale-mode test (`ShortNoteNextToA150CentStepWithVibratoInScaleMode`, 36 of 36) meets the requirement. The free-mode
  case stays a documented limit in ADR 0004, Amendment 5: no DSP change, and the test stays disabled as its record.
- **The 60 to 80 cent known limit:** on dev seeds only, scale mode gives 0.996 against 0.824 in free mode (ADR 0004, Amendment 5).
  No sealed gate was registered for it.

### B. Revisit the ADR 0004 glitch rule after ADR 0007: **open until ADR 0007 is implemented** (Kelechi, 2026-11-28)

- **The rule:** short off-pitch runs are folded into the surrounding note. ADR 0007 (octave errors on weak fundamentals) changed what the
  tracker sees, so the rule's thresholds were tuned on inputs that no longer occur.
- **Done means:**
  - The rule is re-measured on dev seeds with the current tracker, in free mode and in scale mode.
  - It is kept or changed, with the result recorded in ADR 0004.
  - Any change follows the DSP freeze (an ADR, motivated by a real-audio result or a CI failure) and passes the golden check, or comes
    with a new golden tag if it changes free mode.
  - Gate results are re-checked on dev seeds; the spent sealed sets are never re-run.

## Known CI issue (kept as is, Kelechi 2026-11-28)

The on-device database test on the iOS Simulator hangs on its first attempt after a fresh build, right after "Xcode build done". #42
handles it: a fresh boot, a 10-minute limit per attempt, one retry, a step limit. The retry passes in about 1.5 minutes. Each iOS run
loses about 10 minutes. The cause (install, launch or VM-service connection) is not being chased now.
On #45 (2026-11-28) both attempts hung once; a re-run passed on the first attempt. When the retry is not enough, the job fails and
is re-run by hand.

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
