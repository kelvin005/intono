# ADR 0003: Note summaries in the C API (`intono_read_notes`)

Status: Accepted (Kelechi, 2026-11-21). Partly superseded by ADR 0004: the note boundaries (pitch-step onsets), the head/tail trimming of the statistics and the discard threshold (now 10 frames) are replaced there; the C API in this ADR is unchanged.

## Context

Scale grading (Phase 3) and the session log need one record per played note: which note, how far off, how steady, whether it had vibrato. `intono_frame` carries per-hop data only, and ADR 0001 says grading uses the whole-note mean of the raw pitch, not the displayed vibrato centre. Building that on the Dart side would mean shipping every frame across the FFI boundary and duplicating note logic in a second language. ADR 0002 left this as the one open item that touches the C API contract.

## Decision

Add one struct and one function to `intono.h`. Nothing existing changes.

```c
typedef struct {
  double t_start, t_end;       // window-centre time of the first and last voiced frame, seconds
  int    midi_note;            // nearest target of the configured tuning, for the mean pitch
  float  mean_cents;           // whole-note mean of the raw pitch vs that target
  float  std_cents;            // population std of the raw pitch
  float  vibrato_rate_hz, vibrato_width_cents;  // 0 unless >= 30% of the frames carried a vibrato reading
  float  mean_confidence;
  int    frame_count;          // voiced frames in the note
} intono_note;
int intono_read_notes(intono_engine*, intono_note* out, int max);   // UI thread
```

The C++ side builds the notes (`dsp/src/notes.hpp`) and pushes them on a second SPSC ring of 64 entries, separate from the frame ring. The audio thread never blocks: if the UI stops reading, the newest notes are dropped. `intono_read_notes` follows the same thread rule as `intono_read_frames`.

### Segmentation rules

- A note is a run of voiced frames. It ends at the next onset flag (ADR 0002) or after more than 20 consecutive unvoiced frames (about 107 ms, the same figure ADR 0002 uses for "still the same phrase"). A shorter dropout stays inside the note.
- Notes under 10 voiced frames (about 53 ms) are discarded as glitches.
- A pitch-step onset is recognised about 30 ms after the pitch moved, so it carries a rewind: that many of the newest frames are moved into the new note. 5 frames for an abrupt step, 8 for a smeared one.
- The note is emitted when it ends, so it arrives up to ~107 ms late. There is no flush call; to read the last note of a recording, feed about 120 ms of silence (the CLI's `--notes 1` does this).
- Statistics use the raw guarded pitch. The first 4 frames of a note (a 1024-sample window needs four hops to fill) and the last 3 (release, or the smear of a legato step) are left out of mean, std, confidence and the vibrato figures. They still count in `frame_count`, `t_start` and `t_end`.
- `midi_note` and `mean_cents` come from the mean pitch against the nearest target in the current tuning, using the tonic set at the moment the note is emitted.

### Change to ADR 0002's onset rule, found while testing this

The first phrase tests missed legato steps. The 21 ms analysis window smears an abrupt step over about three frames, so a one-semitone step can arrive as 11, 45, 44, 12 cents, or as 17, 27, 23 cents with every piece under the 30-cent jump rule. Two fixes:

1. Consecutive "jump" frames no longer restart the confirmation. The second jump frame was overwriting the reference pitch with the already-moving displayed centre and cancelling a valid onset.
2. A second trigger: the pitch has settled (last frame-to-frame change under 15 cents) and is more than 50 cents from where it was 4 frames ago. The confirmation rule is unchanged: the new pitch must stay more than 50 cents from the old displayed centre for about 30 ms. A 200-cent portamento over 150 ms moves 28 cents in 4 frames and never triggers.

## Measured

On labelled synthetic phrases (`tools/accuracy/ref/synth.py`, 72 phrases × 8 notes, separated and legato, ±40 cents detuning, 40% of notes with vibrato, clean / 20 dB / 10 dB SNR). Gates were proposed before the first run (precision and recall ≥ 0.98, steady-note cents MAE < 3).

| | Precision | Recall | Steady MAE ¢ | Vibrato MAE ¢ |
|---|---|---|---|---|
| dev set (seed 21), used while fixing the above | 1.000 | 1.000 | 0.13 | 1.15 |
| held-out seeds 77, 123, 2024 | 0.993–1.000 | 0.965–1.000 | 0.10–0.84 | 0.99–1.58 |
| all 576 notes | 0.996 | 0.988 | 0.30 | 1.18 |

C++ and the Python mirror agree on every note of the dev set (same count, same note numbers, same frame counts, mean/std within 0.0005 cents, same onset flags frame by frame).

## Known limits

All the misses on the held-out seeds are legato steps that merged two notes:

- A step under 50 cents is not a note change (a very flat or sharp semitone). Intended: the same rule as `is_onset`.
- A step of roughly 50 to 75 cents into a note with wide vibrato (50 cents peak-to-peak or more) can fail the confirmation, because the vibrato brings the raw pitch back within 50 cents of the old centre. Telling these apart needs a full vibrato cycle of look-ahead, about 170 ms, which would delay every onset. Not done.
- Two legato notes of the same pitch cannot be split; nothing in the signal changes.
- A slow portamento (no jump, no step) stays one note with a large `std_cents`. A consumer can tell it from poor intonation by the width of the pitch range, not by `vibrato_width_cents`.
- A loud accent that raises the RMS by more than 6 dB inside a note splits it.
- `mean_cents` of a vibrato note is the mean of the raw pitch over the note, so partial vibrato cycles bias it by up to about a third of the vibrato amplitude divided by the number of cycles: 1.2 cents MAE here on 25–70 cents peak-to-peak. For tighter scale grading, use the centre of the displayed pitch over the note's frames.
- All of this is synthetic. Real violin recordings (URMP) have not been run.

## Consequences

- `intono.h` is a contract: this ADR is the change record. The thread-safety header comment and the semantics block list the new call and the "no flush" rule.
- The real-time safety test now also covers note emission (no allocation, no lock, at least 4 notes produced inside the armed region).
- Cost: the segmenter adds a few dozen floating-point operations per hop.
- Thresholds (20 frames, 10 frames, 4/3 trimmed frames, 50 cents / 15 cents / 4 frames) are constants in `dsp/src/engine.cpp` and `dsp/src/notes.hpp`.
