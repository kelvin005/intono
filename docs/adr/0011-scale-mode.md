# ADR 0011: Phase 3 scale mode (scale data, grader, score-informed segmentation, scale screen, finger/string results)

Status: **Proposed** (2026-11-27). Item 1 (scale data) is implemented in the PR that adds this ADR; items 2 to 5 are designed here at the
level needed to order the work and are filled in by their own PRs. **Not yet checked against the architecture doc's sections "Practising
without staring", "Coaching" and "Match my A"**: that document is not in the repository, the Project store or Google Drive, so it could
not be read. Anything below that conflicts with it gives way to it. Needs Kelechi's answers to the questions at the end, then "merge".

## Context

Phase 3 starts with scale mode (Kelechi, 2026-11-27), in this order: (1) scale definitions as data; (2) a scale grader over
`intono_read_notes`; (3) score-informed segmentation, the hard Phase 3 gate (ADR 0004, `phase-3-plan.md`): recall >= 0.995 on short
notes (100 to 250 ms) with a 100 to 150 cent neighbour step, on a fresh sealed set; (4) the scale screen; (5) finger/string mapping of
results, stored locally (input to the heatmap and spoken tips).

## Decisions

### 1. Scale definitions as data (implemented)

- `app/assets/scales/beginner.json`, **generated** by `tools/scales/gen_scales.py` (no note or finger typed by hand). CI fails if the
  committed file differs from what the generator makes.
- Keys, beginner first: G, D, A, C, F major; A, D, E minor in natural, harmonic and melodic forms (melodic ascends with a raised 6th and
  7th and descends natural). 1 octave for every scale; 2 octaves where both fit first position (G3 to B5): G and A major, A minor in all
  three forms. 19 scales.
- Each scale: ascending, then descending, the top tonic once. Notes as **MIDI numbers with key-correct spelling** (B♭ in F major, D♯ in
  E harmonic minor). **No frequencies**: the A4 reference and the tuning system belong to the grader, so the data does not change when
  the reference does (presumably what "Match my A" sets; to be confirmed against the doc).
- **First-position fingering per note:** the lowest string on which the note is 0 to 6 semitones above the open string (an open string
  rather than a 4th finger, the usual beginner choice), the E string up to +7 (B5). Finger 0 open, 1 (+1 low, +2), 2 (+3 low, +4 high),
  3 (+5, +6 high), 4 (+7). Low/high placement is stored where a finger has two places.
- Dart model `ScaleLibrary` / `ScaleDef` / `ScaleNote`. The tests check the data **independently of the generator**: pitch from
  string + finger, intervals per type in both directions, spelling against pitch, one letter per step, range, shape.

### 2. Scale grader (next PR)

- Input: the expected `ScaleDef` and the notes from `intono_read_notes` (`midi_note`, `mean_cents`, `t_start`, `t_end`, `frame_count`,
  confidence), collected while the scale is played. Pure Dart, no audio.
- **Alignment:** dynamic-programming alignment (edit distance) of the played note sequence to the expected one, with substitution cost
  from the pitch distance, so a missed note, an extra note (a repeated or slipped note, an octave error, a stray speech note) or a wrong
  note are each one edit and the rest stays aligned. Same-pitch splits are merged before alignment (Kelechi, deferred from ADR 0004).
- **Grade per expected note:** 🟢 within ±5 cents, 🟡 within ±15 cents, 🔴 beyond, missed if unaligned. Cents measured against the
  target in the configured tuning and A4 reference. **Thresholds are configuration, not code** (question 1).
- **Score %:** the share of expected notes graded 🟢 (question 2 asks whether 🟡 counts half).
- Tests first, on synthetic note sequences (missed, extra, repeated, octave error, merged, every grade boundary), then on the engine's
  own output for the synthetic phrase sets.

### 3. Score-informed segmentation (the hard gate)

- In scale mode the app knows the expected next note. The note HMM's switching cost toward that state is lowered (ADR 0004 "Known
  limit"), so a short note 100 to 150 cents from its neighbour is visited. This is a **DSP change and a C API change** (the engine has to
  be told the expected sequence or the next note): its own ADR, with the sealed set pre-registered before any run (seeds and hash), one
  run, reported as measured. Free mode is unchanged (identical output, G7). Also before Phase 3 closes: the disabled
  `DISABLED_ShortNoteNextToA150CentStepWithVibratoKnownLimit` passes, and the ADR 0004 glitch rule is revisited after ADR 0007.

### 4. Scale screen

Choose a scale → **glance view** while playing (the whole screen one colour: the grade of the current note, readable from the music
stand without reading text) → results: every note coloured, the score, "play again". Exact behaviour follows "Practising without
staring" once read.

### 5. Finger/string results, stored locally

Each graded note keeps its string and finger from the scale data, so a session's results become per-(string, finger, placement)
statistics stored on the device (never audio). They feed the heatmap and spoken tips ("Coaching"). Storage format and retention in the
item 5 PR.

## Questions for Kelechi

1. **Remote config for the grade thresholds:** which service? There is no backend in the repository yet (no `openapi.yaml` on `main`),
   and a remote-config service is a new vendor (standing rule: ADR and your choice first). Proposal until then: thresholds in a bundled
   config file with the same keys, read through one interface, so the remote source can be swapped in without touching the grader.
2. **Score %:** 🟢 only, or 🟢 = 1 and 🟡 = 0.5?
3. **Fingering choice:** open strings rather than 4th fingers (as generated). Some teachers prefer 4th fingers in scales from the start
   (e.g. a fourth-finger D on the G string). Keep open strings for the beginner set?
4. **The architecture doc:** please add it to the Project (or paste the three sections), so items 2, 4 and 5 can be checked against it.

## Consequences

- No change to `intono.h`, the DSP, a gate or a threshold in item 1. Item 3 will change the DSP and the C API by its own ADR.
- New files only: the generator, the asset, the Dart model and its tests, a CI check.
