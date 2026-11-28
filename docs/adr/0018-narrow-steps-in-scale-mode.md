# ADR 0018: Narrow semitone steps in scale mode (60 to 80 cents)

Status: **Proposed.** Kelechi authorised the DSP-freeze exception on 2026-11-28 ("scale-mode decoder work under the DSP freeze, dev seeds
only, golden free-mode identity unchanged"). The gates below are his; the sealed sets are pre-registered in
`docs/adr/sealed-p3semi-preregistration.md`. The PR needs Kelechi's "merge": it adds an ADR, two gates and a decoder change.

## Context

ADR 0004 (Amendment 5) records the other Phase 3 known limit: steps of 60 to 80 cents (a student 30 cents flat), measured only for an
**isolated** narrow step inside ordinary runs (0.996 in scale mode on dev seeds). A set in which **every** step is narrow was not
measured. On dev seeds 9561 to 9576 the engine of `main` (scale mode, ADR 0014) scored:

| Set | Notes | Recall | Invented |
|---|---|---|---|
| (b) stress: every step 60 to 80 cents | 2846 | **0.891** | **1.93 %** |
| (a) realistic: major scales, every note detuned 0 to 40 cents, either way | 3333 | 0.9955 | 0.33 % |

So the realistic case was close to passing; the stress case was far off.

## Why it failed

The note HMM (ADR 0004) has one state per semitone with a cost-free zone of **+-50 cents** around its centre (so vibrato up to +-50 costs
nothing). Two notes 70 cents apart, each played 20 to 40 cents off its semitone, both fit mostly inside the **neighbouring** state's
zone: a note 37 cents sharp of E is 63 cents from F, 13 cents outside F's zone, which costs 0.5 per frame. Over a 100 to 150 ms note
that is 5 to 8, less than the cost of switching (8 even with the scale bias). The path never switched, and two notes merged into one.
A second, smaller failure: a note's reported semitone is the nearest to its **mean**, and the mean of a sharp note with vibrato and a
contaminated head wanders past the +-50 boundary (73 played 36 cents sharp reported as 74).

## Decision proposed (two constants, scale mode only)

1. **`kHmmScaleTolerance = 30`** (notes_hmm.hpp): while the decoder has steps to follow (scale mode, `nb_ > 0`), the cost-free zone of a
   semitone state is +-30 cents instead of +-50. Free mode (no expected sequence) keeps +-50: **byte-identical to today**.
2. **`kScaleLabelWindow = 60`** (score_cursor.hpp, used in `emit_note`): in scale mode a note whose mean is within 60 cents (re the
   tuning's own target) of either of the next two notes due (`expected[k]`, `expected[k+1]`) is labelled as that note, even if another
   semitone is nearer; `mean_cents` is then measured against that note's target. Free mode and a plain (dropped-bias) cursor: the
   nearest target, as before. No C API change (`intono.h` unchanged), no change to the fixed lag, the fit or the glitch rule.

Both were chosen **on dev seeds only** (9561 to 9576 for the new sets; 9501 to 9516 and 9521 to 9536 as non-regression), never on a
sealed set.

| Constant | Values tried | stress recall / invented | realistic recall / invented | deviation dev (9521 to 9536) |
|---|---|---|---|---|
| tolerance | 50 (before) | 0.891 / 1.93 % | 0.9955 / 0.33 % | |
| | 40 | 0.968 / 0.84 % | 0.9958 / 0.33 % | |
| | **30** | **0.982 / 0.56 %** | 0.9955 / 0.39 % | |
| | 20 | 0.982 / 0.53 % | 0.9958 / 0.36 % | |
| label window (with tolerance 30) | 55 | 0.982 / 0.56 % | 0.9970 / 0.24 % | 0 invented, recall 1.0000 |
| | **60** | **0.982 / 0.56 %** | **0.9979 / 0.15 %** | **0 invented, recall 1.0000** |
| | 70 | 0.981 / 0.63 % | 0.9979 / 0.15 % | 1 invented, recall 0.9987 |

30 is the weakest change on the plateau 20 to 30; 60 the weakest window that gets the whole gain without touching the deviation set.
The stress failures that remain are notes with wide vibrato on a narrow step next to another vibrato note (a trill of 100 ms notes with
+-25 cent vibrato on every note is beyond what the pitch track holds): the stress gate is therefore 0.97, not 0.99.

## What this does not change

- The C API, the fixed lag (so the 350 ms note-delay gate), the change-point fit, the glitch rule, the cursor's state machine.
- Free mode: golden manifest 288 of 288 identical (inline; threaded in CI).
- ADR 0014's gates: dev seeds 9501 to 9516 and 9521 to 9536 give the same results as before (short runs 1.0000, deviations 0 invented).

## Gates (Kelechi, 2026-11-28; pre-registered in `sealed-p3semi-preregistration.md`)

| Set | Gate |
|---|---|
| **p3real** (a) realistic scales, every note detuned 0 to 40 cents (seeds 34601 to 34616) | recall **>= 0.99**; invented notes **<= 0.5 %** of truth notes; hard |
| **p3semi** (b) stress, every step 60 to 80 cents (seeds 34501 to 34516) | recall **>= 0.97**; invented reported, not gated |

Each set runs once with the frozen binary built from the merge of this PR.

## Risks

- **Narrower zone, more splits from vibrato in scale mode:** watched by the invented-note rates on every set above and by the
  unchanged deviation set (a player's wrong note must still be reported as the note played).
- **Label window and wrong notes:** a note played 40 to 60 cents off a due note, but meant as the neighbour, is shown as the due note.
  In scale mode a note that is 60 cents from the due note is the due note for grading purposes (the grade would say "60 cents flat"
  either way); the deviation dev set shows no loss. Window 70 did lose one.
- **Real audio:** none of this is measured on a real violin yet; it is the next real-clip check.

## Tests (written first)

`NoteTracker.ScaleModeSeparatesSemitoneNotesPlayed20To40CentsOff` (a trill of 70-cent steps without vibrato, 16 cases: failed before,
all pass),
`NoteTracker.ScaleModeNarrowTrillWithVibratoStaysUnderTheMeasuredFailures` (the same with +-12 cent vibrato on every note, phase-locked,
the hardest case: 12 of 16 failed with the old +-50 tolerance, 7 of 16 fail now; the bound pins that and is lowered when the decoder improves),
`EngineNotes.ScaleModeLabelsANoteWithinSixtyCentsAsTheDueNote` (fails with window 0; free mode keeps the nearest target).
