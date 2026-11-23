# Phase 3 plan: hard gates recorded so far

No Phase 3 plan existed in the Project store when this was written (2026-11-22); this file holds only what has been decided so far, and the full plan still has to be written.

## HARD gate: semitone steps in short notes (Kelechi, 2026-11-22)

Phase 3 cannot close until score-informed segmentation in scale mode reaches **recall >= 0.995** on short notes (100 to 250 ms) whose smaller adjacent centre step is **100 to 150 cents**, measured on a fresh, pre-registered sealed set.

- Why: in the informational sealed run (seeds 34101 to 34108, ADR 0004) the engine recovered 0.924 of notes with a 100 to 130 cent neighbour step (45 of 594 missed) and 0.979 at 130 to 150 cents. The cause is the note HMM's emission/switching cost, not the change-point fit.
- Mechanism: lower the switching cost toward the expected next note of the scale (the usual cost to every other state), so a note within about 100 to 150 cents of its neighbour is visited.
- Same sealed-set rules as before: seeds and hash fixed first, frozen binary, one run, reported as measured, a failed set is never reused.
- Also required before Phase 3 closes: the disabled unit test `DISABLED_ShortNoteNextToA150CentStepWithVibratoKnownLimit` (ADR 0004) passes; the ADR 0004 glitch rule is revisited after ADR 0007.
- Deferred by Kelechi: same-pitch splits are merged by the Phase 3 scale grader.
