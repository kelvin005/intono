# Sealed sets "p3real" and "p3semi": pre-registration of the narrow-step gates (ADR 0018)

Registered: 2026-11-28 (Africa/Lagos), on `main` at `32b5369`, with the decoder change of ADR 0018 on its dev seeds, **before** any clip of
either set was generated or scored. Both runs refuse until the frozen-binary addendum below is written (the runner's `pending` flag).

## The gates (Kelechi, 2026-11-28)

| Set | What it is | Gate |
|---|---|---|
| **p3real** (a) realistic | normal beginner scales: 6 to 8 notes of a major scale, up or down, every note detuned by an independent 0 to 40 cents either way | recall **>= 0.99**; invented notes **<= 0.5 %** of truth notes; both hard |
| **p3semi** (b) stress | every step between neighbours is a semitone played so the centre step is 60 to 80 cents (notes 20 to 40 cents flat or sharp) | recall **>= 0.97**; invented reported, not gated |

Scale mode in both: each phrase's truth MIDI sequence is given to the engine as the expected sequence (as the scale screen does).

## Sets

| | p3real | p3semi |
|---|---|---|
| Seeds | **34601 to 34616** | **34501 to 34516** |
| sha256 of "seed,seed,..." | `966768fd118e818c527d63c76d427ee4d4a70f40a8c5eae5ce856329b6871d15` | `408e17b39cd9ae68342680819eea3777357da2e1c20cc96a2c02aad220f1e6b2` |
| Generator | `semitone_set.build_realistic_set(seed, n=30)` | `semitone_set.build_semitone_set(seed, n=30)` |
| Expected size (dev, 16 seeds) | about 3300 notes | about 2850 notes |

Seeds 34501 to 34516 were reserved on 2026-11-28 (the earlier, unmerged draft of this registration) and were never generated; 34601 to
34616 appear nowhere in the repository. The dev seeds are 9561 to 9576 for both sets (disjoint from every sealed seed).

Both phrases are built from `synth.make_phrase` (called, not changed): notes of 100 to 250 ms (first and last 250 to 400 ms), a 30 to 70 ms
bow dropout before a middle note in about a third of the phrases, half the notes with vibrato of +-15 to +-30 cents at 5 to 7 Hz, SNR 20 to
35 dB; all notes within MIDI 56 to 86. (a): a major scale from a random tonic and starting degree, up or down; each note's detune is
|d| uniform in 0 to 40 cents with a random sign, independently (so a half step can be as small as 20 cents). (b): every step one semitone
in a random direction (flipped to keep the note in range and within +-40 cents of its semitone), its centre size drawn from 60 to 80 cents.

## Scoring

A truth note is found if the engine reports a note with its MIDI number and an onset within 80 ms (each engine note used once). An engine
note matching no truth note is invented. Recall of the 100 to 250 ms notes is reported as well, not gated.

## Dev results the parameters were chosen on (dev seeds 9561 to 9576; not the sealed sets)

| | Recall | Invented |
|---|---|---|
| (a) realistic, `main` before ADR 0018 | 0.9955 | 0.33 % |
| (a) realistic, with ADR 0018 | 0.9979 | 0.15 % (5 of 3333) |
| (b) stress, `main` before ADR 0018 | 0.891 | 1.93 % |
| (b) stress, with ADR 0018 | 0.9817 | 0.56 % (16 of 2846) |

Expected from dev: (a) passes with margin on recall and on invented notes; (b) passes recall 0.97 with about a point of margin.
Anything that differs on the sealed sets is reported as measured.

## Protocol

- After the implementation PR (ADR 0018) is merged: build the frozen binary from the merge commit; an **addendum** to this file records its
  path and sha256 and the sha256 of `semitone_set.py`, `run_semitones.py` (with the `pending` flag removed), `synth.py` and `notes_hmm.hpp`.
  Registration hashes (this version): `semitone_set.py` 4f16ef95f00bf83d0da140f52d3797df4cdc32134bcb171d3e65f91615c75b73,
  `run_semitones.py` 99d8f06b225eb7b15c229f955fc688c3307f50e6d5bff7322f3a52bd5b017d1a (refuses both sets), `synth.py`
  162a48efca0b97ec56c4435991a44102b496410a3b1dd97cf2f33aff7f9862fa (unchanged since sr1).
- One run of each: `python3 -I tools/accuracy/run_semitones.py --sealed p3real --cli <frozen>` and `--sealed p3semi --cli <frozen>`. The runner
  refuses a second run of either, and a seed list that does not match its hash.
- Reported as measured. A set that fails is never reused and no parameter is chosen on it: fix on dev seeds, register a new set.
- Phase 3 does not close on these gates alone: free mode byte-identical (golden manifest) and the ADR 0004 glitch-rule revisit stay open.
