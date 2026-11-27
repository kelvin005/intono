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

## Second set: "p3dev", invented expected notes (Kelechi, 2026-11-27; registered before any implementation)

A false note is worse than a missed one, so this gate is as hard as the recall gate. The p3gate set plays exactly the expected notes, so
it cannot show the engine inventing one; this set does.

- Seeds: **34301 to 34316** (16 seeds x 64 phrases = **1024 deviations**, 256 of each kind). Never used. sha256 of
  "34301,34302,...,34316": **6c44e218bb711a378ec6c0faf9d89ee4b3c8e5966f80fb370a8762b6ebbde295**
- Generator and scoring: `tools/accuracy/ref/deviation_set.py`, sha256 **a0879aa41c5d5fbabfd52aa09789920f6969d84aabc87321de2dafe8cd247299**
  (calls `synth.make_phrase`; `synth.py` unchanged, 162a48ef...62fa). Each phrase: a 10-note diatonic fragment (up, then down once),
  the expected sequence E given to the engine, played with exactly one deviation at a position 2 to 7: **wrong** (1 or 2 semitones off
  E[p]), **skip** (E[p] not played; never at the top of a turn), **repeat** (E[p] twice, re-bowed with a 30 to 70 ms gap), **off-scale**
  (a pitch not in E inserted before E[p]). Notes 120 to 400 ms, detune +-20 cents, half with vibrato, SNR 20 to 35 dB.
- Scoring (in the same file): **invented** = the engine reports the invented MIDI number starting inside the event's window (wrong:
  E[p] within +-80 ms of the wrong note's onset; skip: E[p] between the onset of the note before the gap + 80 ms and the onset of the
  note after it + 80 ms; repeat: E[p+1] within +-80 ms of the repeat's onset; off-scale: E[p] within +-80 ms of the inserted note's
  onset). **Recall** = the played deviation notes (wrong, repeat, off-scale; 768) found with the same MIDI number and an onset within
  80 ms.
- **Gates (Kelechi): invented-expected-note rate <= 0.5 % of deviations** (at most 5 of 1024); **recall of the played deviation notes
  >= 0.98**.
- Runner: `tools/accuracy/run_deviations.py` (sha256 a3644aca7e999124d6556550d7e309ed087a69bd7d48067a0d819f31940c7cdb at registration),
  registry `SEALED["p3dev"]`, refused until `intono-cli --expected` exists. Dev seeds **9521 to 9536** (unused); checked here on 9521 to
  9523 only (generator invariants, no engine): 48 deviations of each kind; a perfect engine scores 0 invented and recall 1.0, one that
  reports the expected note at every deviation scores 16 of 16 invented.
- Same protocol as p3gate: the addendum before the run records the frozen binary and the final runner hash; one run; reported as
  measured; a failed set is never reused.

## Addendum: frozen binary and hashes (2026-11-27, written before either sealed run)

Neither p3gate nor p3dev has been generated or run before this addendum. The parameters were chosen on the dev seeds only:
`kHmmSwitchExpected` = 8 with the entry rule (ADR 0014 Amendment 1, approved by Kelechi 2026-11-27). Dev results are in
`tools/accuracy/reports/phase3/score_informed_dev.md`: G-P3 0.9981, invented 0 of 1024, deviation recall 0.9987.

- **Source:** `main` at `fc29130`, the merge of #34. Built in a clean worktree with `cmake -G Ninja -DCMAKE_BUILD_TYPE=Release
  -DINTONO_BUILD_TESTS=OFF`, GCC 13.3.0, CMake 3.28.3, Linux x86-64.
- **Frozen binary:** `/home/claude/frozen/intono-cli-fc29130` (read-only), sha256
  **9e77f56f1519f40c126c4b9a9ccd61a1f6ad7ca85f1f188a2688c5599d7d00f7**.
  - Check before the run: the golden manifest in free mode gives 288 comparisons, 0 differ.
  - Check before the run: dev seed 9507 in scale mode gives the dev result.
- **Source hashes at `fc29130`:**

  | File | sha256 |
  |---|---|
  | `dsp/src/notes_hmm.hpp` | 49ed070fe1344d16e9066e5821e07653a959b8facb6d22fb1e0bd40de6960aab |
  | `dsp/src/score_cursor.hpp` | aeeca312b49afda316cf1672b8f5777fa3682bb3143531bba64b90966fa5f1c1 |
  | `dsp/src/engine.cpp` | e09e246c6c56614e41e789ce3164a47e4f0d8051e41796a1ab1cd3da4dfc7b09 |
  | `dsp/include/intono/intono.h` | 489440d97308399a7a15ad10b1636e9961ea990c45c0f3a199902c8ef9eb0a4e |
  | `tools/accuracy/ref/synth.py` | 162a48efca0b97ec56c4435991a44102b496410a3b1dd97cf2f33aff7f9862fa (unchanged since sr1, as registered) |
  | `tools/accuracy/ref/deviation_set.py` | a0879aa41c5d5fbabfd52aa09789920f6969d84aabc87321de2dafe8cd247299 (as registered) |

- **Runners as they run, with this addendum's edit:** that edit removes only the `pending` refusal; seeds, hashes and gates are unchanged.

  | File | sha256 |
  |---|---|
  | `tools/accuracy/run_short_runs.py` | b67eb565e400bd77eff7a6062126e74c0d36a5b752d8c01c1766d7f2eaf8b332 |
  | `tools/accuracy/run_deviations.py` | a27ce98d9994edd060f6b8243bb216a9f83362905e8ba8f9108666aeccb9d61a |

- **Runs:** once each, from `main` after this addendum merges, results reported as measured:
  - `python3 -I tools/accuracy/run_short_runs.py --sealed p3gate --cli /home/claude/frozen/intono-cli-fc29130`
  - `python3 -I tools/accuracy/run_deviations.py --sealed p3dev --cli /home/claude/frozen/intono-cli-fc29130`
