# ADR 0011: Phase 3 scale mode (scale data, grader, score-informed segmentation, scale screen, finger/string results)

Status: **Accepted** (Kelechi, 2026-11-27; answers below). Item 1 (scale data) is implemented in the PR that adds this ADR; items 2 to 5
are designed here at the level needed to order the work and are filled in by their own PRs. Checked against `docs/architecture.md`
("Feature modules", "Scale grading rules", "Coaching", "Practising without staring", "Match my A"); where this ADR differs from the doc,
the difference and Kelechi's decision are stated below. v1 scope (no accounts, no backend, one-time Pro unlock) is ADR 0012.

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
- **The grade uses the note's mean pitch, not the live display value** (architecture doc, ADR 0001): `intono_note.mean_cents` against the
  target in the engine's current tuning and A4 reference. Cents to the expected note when the engine's nearest note differs:
  `(midi_note - expected) * 100 + mean_cents` (exact in equal temperament; just and Pythagorean need per-degree offsets and come with the
  tuning-system work).
- **A note counts when it lasts 150 ms or more** (architecture doc). Shorter notes are not graded: they are dropped before alignment, so
  a glitch does not shift the grades; an expected note played that short is reported as missed. Configurable (`min_note_ms`); see the
  question below on short notes.
- **Alignment:** edit-distance alignment of the played sequence to the expected one, substitution cost from the pitch distance, so a
  missed note, an extra note (a repeated or slipped note, an octave error, a stray speech note) or a wrong note is one edit and later
  grades do not shift. Same-pitch splits are merged before alignment (Kelechi, deferred from ADR 0004).
- **Grade per expected note:** 🟢 within ±5 cents, 🟡 within ±15 cents, 🔴 beyond, or missed (counted as 🔴 in the score).
- **Score % = (🟢 + 0.5 × 🟡) / expected notes** (Kelechi, 2026-11-27; this replaces the architecture doc's "share of notes within ±10¢").
  The 🟢 / 🟡 / 🔴 counts are shown next to the %.
- **Thresholds come from a config file bundled with the app** (v1, no remote-config vendor): `grade_green_cents` 5, `grade_yellow_cents`
  15, `min_note_ms` 150, read through one interface so a different source could replace it later without touching the grader.
- Tests first, on synthetic note sequences (missed, extra, repeated, octave error, merged, short, every grade boundary), then on the
  engine's own output for the synthetic phrase sets.

### 3. Score-informed segmentation (the hard gate)

- In scale mode the app knows the expected next note. The note HMM's switching cost toward that state is lowered (ADR 0004 "Known
  limit"), so a short note 100 to 150 cents from its neighbour is visited. This is a **DSP change and a C API change** (the engine has to
  be told the expected sequence or the next note): its own ADR, with the sealed set pre-registered before any run (seeds and hash), one
  run, reported as measured. Free mode is unchanged (identical output, G7). Also before Phase 3 closes: the disabled
  `DISABLED_ShortNoteNextToA150CentStepWithVibratoKnownLimit` passes, and the ADR 0004 glitch rule is revisited after ADR 0007.

### 4. Scale screen

Choose a scale → **glance view** while playing (the whole screen green, yellow or red: the grade of the note just finished, read in
peripheral vision from the music stand) → results ("play, then review"): every note coloured, the score with the 🟢/🟡/🔴 counts, "play
again". The architecture doc's "tap-to-replay of the student's own audio" is **not** in this item: it means keeping the run's audio on the
device, which the standing rule ("never log or upload audio") does not cover yet (question 2).

### 5. Finger/string results, stored locally

Each graded note keeps its string and finger from the scale data, so a session's results become per-(string, finger, placement)
statistics stored on the device (never audio), in the doc's local database (SQLite via drift; `sessions` and `note_stats`, with
`string`, `finger` and `placement` added so the heatmap is per finger, as "Coaching" asks). They feed the finger-level heatmap and the
templated tips, which come after item 5. No outbox or sync tables (ADR 0012).

## Answers (Kelechi, 2026-11-27)

1. **Thresholds:** no remote-config vendor; a config file bundled in the app for v1.
2. **Score:** 🟢 = 1, 🟡 = 0.5, 🔴 = 0; the green/yellow/red counts are shown next to the %.
3. **Fingering:** open strings by default (standard for beginners); 4th-finger variants can be an option later.
4. **Architecture doc:** in the repository as `docs/architecture.md` (#27). Its Backend, Sync and App-Store-subscription sections are
   outdated (ADR 0012).

## Open questions (raised by reading the doc)

1. **Short notes and the 150 ms rule:** the hard Phase 3 gate is about notes of 100 to 250 ms, and fast scales have semiquavers near
   150 ms. With `min_note_ms` 150 a correctly played 120 ms note is "missed". Keep 150 ms for v1, or lower it (for example to 80 ms, just
   above the ADR 0004 glitch rule's 12 frames = 64 ms)?
2. **Replay of the student's own audio** ("Play, then review"): it needs the run's audio kept on the phone until the review ends
   (never uploaded, deleted after). That is a change to the standing rule and its own ADR. Wanted for v1?

## Consequences

- No change to `intono.h`, the DSP, a gate or a threshold in item 1. Item 3 will change the DSP and the C API by its own ADR.
- New files only: the generator, the asset, the Dart model and its tests, a CI check.
