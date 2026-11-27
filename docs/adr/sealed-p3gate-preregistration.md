# Sealed set "p3gate": pre-registration of the hard Phase 3 gate (written before any implementation)

Registered: 2026-11-27 (Africa/Lagos), on `main` at `200a488`, **before** score-informed segmentation (ADR 0014) exists in any form and
before any clip of this set was generated or scored. The seeds are in the runner's registry (`tools/accuracy/run_short_runs.py`,
`SEALED["p3gate"]`), which refuses them on the dev entry point and refuses the sealed run until the scale-mode runner is written.

## The gate (Kelechi, 2026-11-22; ADR 0004, `phase-3-plan.md`)

**Score-informed segmentation in scale mode reaches recall >= 0.995 on notes of 100 to 250 ms whose smaller adjacent centre step is
100 to 150 cents.** Phase 3 does not close without it.

## Set

- Seeds: **34201 to 34216** (16 seeds x 30 phrases). Never used: 34001-34008 (sr1) and 34101-34108 (sr1info) are spent; 34201+ appear
  nowhere in the repository.
- sha256 of the seed list "34201,34202,...,34216": **10453f5292fda9f51b8bca8014963260fde9c64fe7712e1cc43a7b0f1269a1aa**
- Generator: `synth.build_short_run_set(seed, n=30, min_step_c=100.0, vib_prob=0.5)`, the same as the informational sr1info run:
  phrases of 5 to 7 legato notes of 100 to 250 ms (first and last 250 to 400 ms), steps of 1 to 3 semitones in both directions with every
  centre step >= 100 cents, detune +-30 cents, half the notes with vibrato of +-15 to +-30 cents at 5 to 7 Hz, about a third with a 30 to
  70 ms bow dropout before a middle note, SNR 20 to 35 dB. sha256 of `tools/accuracy/ref/synth.py`:
  **162a48efca0b97ec56c4435991a44102b496410a3b1dd97cf2f33aff7f9862fa** (unchanged since sr1).
- Expected size, from sr1info (same generator, 8 seeds): 594 notes in the 100 to 130 cent band alone, so about 1200 in that band here plus
  the 130 to 150 cent band. At 0.995 the gate allows about 1 miss in 200 band notes.
- Dev seeds for this work: **9501 to 9516** (unused). Parameters (the expected-note switching cost and anything else ADR 0014 adds) are
  chosen on dev seeds only, never on this set.

## Scale mode in the run

Each phrase's **truth MIDI sequence** is given to the engine as the expected sequence (the ADR 0014 API), as the scale screen gives the
scale. The engine is run once per phrase; nothing else is changed per phrase.

## Scoring (as for sr1)

- A truth note is found if the engine reports a note of the same MIDI number starting within 80 ms of its onset (each engine note used
  once). An extra note is an engine note matching no truth note.
- **Gated band:** truth notes with duration 100 to 250 ms (the generator's middle notes) and smaller adjacent centre step (cents, centre =
  100 x MIDI + detune, `smaller_step_c` in the runner) of 100 to 150 cents.

## Gates

| | Limit | Why |
|---|---|---|
| **G-P3 (the hard gate)** | recall >= **0.995** in the gated band | Kelechi, 2026-11-22 |
| Non-regression, same run | recall >= 0.995 for notes with smaller step >= 150 cents and duration >= 150 ms; recall >= 0.98 for notes with smaller step >= 150 cents and duration 100 to 150 ms | the sr1 gates must not be lost in scale mode |
| Non-regression, same run | at most 1 extra note per 200 truth notes | sr1 gate |

Also required before Phase 3 closes, outside this set: free mode (no expected sequence) byte-identical to today (`bit-identity-vs-phase1`
and the golden manifest); `DISABLED_ShortNoteNextToA150CentStepWithVibratoKnownLimit` enabled and passing; the ADR 0004 glitch rule
revisited after ADR 0007.

## Protocol

- Before the run, an addendum to this file records: the frozen binary's path and sha256, the sha256 of `run_short_runs.py` with the
  scale-mode runner (this file's registration hash below is the version that only refuses), of `notes_hmm.hpp` and of `intono.h`, and the
  dev-seed results the parameters were chosen on.
- One run: `python3 -I tools/accuracy/run_short_runs.py --sealed p3gate --cli <frozen binary>`. The runner refuses a second run.
- Reported as measured. If a gate fails: no tuning against this set; fix on dev seeds, register a new set; this one is never reused.

Registration hashes: `run_short_runs.py` b72e888b1d42d23e3b40f16dbd3bef74ca25b1b7da2f4af8a3ca277cd047925f (refuses p3gate),
`notes_hmm.hpp` c204b0f47b0faaefeffa89e854219eb1f18cbb572d6cb69a54923b7a964fd018, `intono.h`
626ebe7f613744e43bb78619381d4ebe96badb78febe964ff7a7452f069017d1.
