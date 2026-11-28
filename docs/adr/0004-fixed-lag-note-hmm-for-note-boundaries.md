# ADR 0004: Fixed-lag note HMM for note boundaries

Status: Accepted (2026-11-22), including Amendments 2 and 3, on sealed set 3 (passed every gate), and Amendment 4. Amendment 4 (boundaries between short notes) passed both of its sealed sets (2026-11-22). Set 1 passed the base design; set 2 failed Amendment 2 and is spent. Known limits: steps of about 60 to 150 cents next to short notes (a HARD Phase 3 gate, see below), same-pitch repeats with no RMS rise, results measured on synthetic audio and glibc only.
Written before any implementation code on Kelechi's instruction (2026-11-21), then amended before the gate run on 2026-11-22 (see "Amendments"). The Android emulator ADR is 0005 and comes after this one.

## Context

ADR 0003 found boundaries from the onset flag (RMS rise, or a pitch step held for ~30 ms). On the dev boundary set (`tools/accuracy/run_boundaries.py --seeds dev`: 300 two-note legato clips, steps of at least 60 cents, vibrato up to ±50 cents at 4–8 Hz, 16 vibrato phases) recall was 0.973 against a required 0.995. All the misses are steps of 60–80 cents, or steps into a note with wide vibrato, where the vibrato brings the raw pitch back within 50 cents of the old centre during the 30 ms confirmation. A rule that looks at 6 frames cannot tell a 60-cent step from a vibrato swing; one that looks at a few hundred milliseconds can.

## Decision

Replace pitch-based note-boundary detection with a fixed-lag hidden Markov model on the raw pitch track, place each boundary with a sinusoid-plus-step change-point fit, and compute note statistics with a guard zone around the boundary. The live path is untouched: `intono_frame` (display pitch, cents, vibrato, `is_onset`) is computed exactly as before and `is_onset` keeps its ADR 0002 rules. Only `intono_note` boundaries and the note statistics change.

### Model (frozen values)

- **States:** one per ET semitone, MIDI 52 to 102 (51 states, covering the 180–3200 Hz range). State `s` is centred at `100·(s − 69)` cents relative to `a4_hz`. The grid is ET in every tuning system; a just or Pythagorean target is at most about 14 cents from ET, well inside the tolerance. `midi_note` and display targets still come from the configured tuning.
- **Observation:** the raw guarded pitch of each voiced frame, `c = 1200·log2(hz / a4_hz)` cents.
- **Emission cost:** `e(c, s) = max(0, |c − centre_s| − 50) / 25`. The ±50 cent flat bottom covers vibrato up to ±50 cents around a note; outside it the cost grows linearly (L1) in units of 25 cents.
- **Transition cost:** 0 to stay, `λ = 24` to move to any other state (a single switching penalty, no preference for small intervals).
- **Decoding:** Viterbi forward pass in O(states) per voiced frame (`δ_t(s) = e_t(s) + min(δ_{t−1}(s), min_s' δ_{t−1}(s') + λ)`), one "stayed or switched" byte per state and the previous-best state per frame; scores are re-based on their minimum each frame. Ties go to the lowest state index.
- **Fixed lag `L = 40` voiced frames (213 ms):** at each voiced frame, backtrack from the currently best state `L` frames and commit the label of the frame that is `L` frames old. The 350 ms summary-delay budget wins over the "about 300 ms" first asked for (see Amendments): the delay of a summary is `L` plus how late the HMM's switch comes after the true step, and the second term reaches ~100 ms for 60–80 cent steps into wide vibrato.
- **Runs:** HMM frames are the voiced frames only. A dropout of up to 20 unvoiced frames (ADR 0003) is skipped inside the run. After more than 20 unvoiced frames the run ends: all pending frames are decoded from the best final state (flush), the last note closes, and the next voiced frame starts a fresh run. A note therefore still closes ~107 ms after the last voiced frame at the end of a phrase, not 213 ms.

### Boundary placement: sinusoid-plus-step change-point fit

When a committed label differs from the previous one at frame `k` (the HMM's proposal), the boundary is placed by a fit over the voiced frames of the ring around it, using frames up to the newest one (no additional delay):

- **Candidates:** a boundary between consecutive voiced frames `j−1` and `j`, for `j` from `k − 24` to `k + 24` (further limited so that each side keeps at least 24 frames, half a 4 Hz vibrato cycle, and the new note starts at least `min_frames` after the previous boundary). The step time of a candidate is the midpoint of the two frame times.
- **Each side of the step** is modelled independently as a constant (1 parameter), or a constant plus one sinusoid of free phase and amplitude (3 parameters) at one of 12 vibrato rates, 3.5 to 9.0 Hz in 0.5 Hz steps, with amplitude capped at 70 cents. Each side uses up to 56 frames next to the step; the sinusoid needs at least 12. The best model per side is chosen by BIC, `n·ln(1 + RSS / (n·σ²)) + p·ln n` with a noise floor `σ = 2` cents (zero for a perfect fit, so candidates that put a different number of frames on each side compare fairly).
- **Smear exclusion:** frames whose analysis window contains the step, i.e. within half a window (10.7 ms) of the candidate time, belong to neither side. This replaces the earlier half-window shift constant.
- **Placement:** the total cost of a candidate is the sum of both sides. The cost is flat over every position whose excluded frames cover the smeared step, so the boundary is the middle, in TIME, of the contiguous run of candidates around the minimum whose cost is within 12 BIC units of it. The new note's first frame is the first candidate frame at or after that time.
- **Veto:** the fitted constants are the levels with vibrato removed. If the level change is less than 25 cents or in the opposite direction to the HMM's state change, the proposal is rejected as vibrato: the note continues and the HMM state is adopted without a split. This is what stops a steady note detuned about 40 cents with ±50 cent vibrato (pitch swinging across the boundary between two states) from being split at its first trough. On dev the smallest fitted level change of a real step is 62.5 cents, and no steady clip produces a valid proposal; 25 leaves 35 cents of headroom for the fit's level error on a 60-cent step (28 cents in the worst deterministic phase combination).
- **Minimum side, no fallback:** a boundary needs a valid fit, so at least 24 frames (128 ms) on each side, except at a run edge (Amendment 2). With fewer frames the fitted level can slide by the vibrato amplitude and the fit cannot tell a level from a swing. An earlier version trusted the HMM's frame when the fit was invalid; that produced a spurious 16-frame tail note on seven of the 10 dB clips and a split at the start of one steady run, so it was removed. Missing a split on a very short note is the safer error for grading.
- **RMS onset** (ADR 0002) still splits a note of the same pitch, at its own time, when its frame is committed. Pitch-step onsets no longer split notes; they still set `is_onset`.
- **Cost:** the fit runs only when the HMM proposes a change. Prefix sums over the window for the 12 rates make the 49 candidates cheap. Measured on the dev host (x86-64, `-O2`), tracker alone: mean 2.0 µs per hop, worst single hop (the one running a fit) 147 µs, against a 5333 µs hop. Phone CPUs are slower; that margin is about 36×.

### Robust note statistics

Statistics are over the raw guarded pitch (ADR 0003) with these frames left out (they still count in `frames` and in the times):

1. a guard zone of 30 ms of time (not frames) after a note start and before a boundary, so dropouts at a noisy step cannot stretch it; at the end of a run, the last 3 frames (release);
2. within 16 frames of a boundary, frames whose displayed vibrato centre (ADR 0001, `NoteFrame.ctr`, cents re 440) is nearer the neighbouring note than this one. For the head of a note the neighbour is the previous note's measured mean and this note is its own measured mean (one refinement pass at close); for the tail of a note the neighbour is the next note's semitone and this note is its own measured mean. A first version compared with the neighbour's semitone for the head too; on dev it threw away half a vibrato cycle of a note detuned toward the neighbour and biased its mean by 2 cents, so it was replaced.

The head test applies to every note that follows a pitch boundary, including the last note of a run (an early version reset its state before closing the last note and skipped it; fixed before the gate run, which moved the dev max from 0.94 to 1.48 cents). A note with no frames left in the statistics, or under 10 voiced frames, is discarded. (Earlier builds had an accidental floor of 13 frames from the old head/tail constants; it is gone.)

### Interface

`intono.h` does not change. Two sentences in its semantics comment change: a note that ends in a pitch change arrives about 213 ms plus the HMM's switch delay (at most about 330 ms measured, Amendment 3) after the true change, and it still arrives about 107 ms after the end of a phrase. The note ring, the 64-note capacity and the `intono_note` fields are as in ADR 0003. `NoteFrame` (internal) gains `ctr`.

Memory, all preallocated in the engine: scores 51 doubles; backpointers 256 × 51 bytes + 256 bytes; frame ring 256 records; fit scratch 12 × 137 × 7 doubles plus three arrays of 137. About 110 KB per engine.

### Python mirror

`tools/accuracy/ref/stream_ref.py` has the same model, constants, tie rules and operation order (HMM, fit, segmenter, statistics) and is compared with the C++ note for note (`run_cpp.py`): same notes, `midi`, `frames`; times, means and standard deviations to the tolerances recorded there.

## Test protocol (fixed before the first gate run)

- **Sets** (`run_boundaries.py`, `ref/synth.py`): two-note legato clips with centre steps of at least 60 cents between different ET notes (detune ±40 cents on each note, steps of 1 to 4 semitones in both directions), vibrato of ±20 to ±50 cents at 4–8 Hz on each note with probability 0.85, the vibrato phase at the step stratified over 16 bins for each note independently, clean / 20 dB / 10 dB SNR; plus steady single notes with ±35 to ±50 cent vibrato at 4–8 Hz and detune ±40 cents.
- **Seeds.** Development: 9101, 9102. Gate: 31001, 31002, 31003, 31004 (600 step clips and 240 steady clips), chosen before any HMM code and never used for tuning. `run_boundaries.py --seeds gate` appends every run to `tools/accuracy/reports/phase1/gate_runs.log`.
- **Gate**, on the gate seeds only:
  - recall ≥ 0.995 and precision ≥ 0.995 for step boundaries (found = a note with the right ET number starts within 100 ms of the true step);
  - 0 false splits on steady wide vibrato;
  - boundary time error `|t_start − true step|`: p95 ≤ 20 ms and max ≤ 100 ms;
  - note-mean error caused by the boundaries: ≤ 2 cents on every note and median ≤ 0.5 cents (median of the absolute error), where the error is the reported mean (cents re 440) minus the mean of the same raw pitch track over the true note interval, leaving out a 30 ms guard at the true boundary and the same run-start and run-end trims the engine applies (first 6 voiced frames of a run, last 3);
  - summary delay, from the true step to the moment the first note is read, at most 350 ms.
- **Dev-set rule:** parameters were tuned on the dev seeds only. The values above are final. A failed gate is reported as failed and the numbers reported as measured; nothing is changed after seeing a gate result.
- **Unit tests, deterministic:** a 60-cent step with ±50 cent vibrato at swept phases splits within 20 ms and within the delay budget; steady wide vibrato at four detunings, three rates and eight phases is never split; a step under 50 cents stays one note; real-time safety (no allocation or lock) with the HMM running; chunk invariance; run flush at a phrase end.
- Steps under 50 cents stay a single note by definition. A step of 50 to 60 cents is undefined either way and is not in any gate.

## Dev evidence (seeds 9101, 9102; 300 step clips, 120 steady clips)

At the frozen configuration: recall 1.000 and precision 1.000 (all 300; 0 spurious notes), 0 false splits on steady vibrato, boundary error median 2.3 ms / p95 14.1 ms / max 19.8 ms, summary delay median 235 ms / max 318 ms, note-mean error median 0.00 / p95 0.44 / max 1.48 cents over 600 notes. All the dev gates pass; that is not evidence for the sealed seeds.

Deterministic stress sweep (unit test, ±50 cent vibrato on both notes at 6 Hz, a 60-cent step, 24 phase combinations): all split, 18 of 24 boundaries within 20 ms, worst 64.7 ms. Clips as hard as this are the tail of the dev and gate sets, not their typical case.

What was tried and dropped, all on dev or in unit tests: quadratic emission with λ = 12 (false splits on steady vibrato and spurious notes); λ = 28, 32, 40 (steady splits not fixed, recall or precision and the delay budget missed); lag 48 and 56 (delay 360–403 ms); a pull toward the nearest semitone inside the tolerance band (μ = 0.25 to 2: false splits grow from 1 to 132 clips); the steepest transition of the 4–6 frame mean (boundary error up to 94 ms); a plateau tolerance of 3 and 6 BIC units (max error 23 and 21 ms), 10 to 15 (max 18–20 ms), 20 (steady-vibrato unit test fails); a 6- or 12-frame minimum side with a fallback split (spurious tail notes, steady run-start split); a veto at 35 cents (a real 60-cent step fitted at 32.2 cents is lost); comparing a note's head with the neighbour's semitone (2-cent bias, see above).

## Amendments to the version written before the code (2026-11-22, before any gate run)

- Emission quadratic → L1; λ 12 → 24; lag 56 (299 ms) → 40 (213 ms). Evidence above; the 350 ms delay limit takes precedence, as instructed.
- Boundary placement: steepest transition of the 6-frame mean (search 16 frames back) → the sinusoid-plus-step fit with the veto (search 24 back and 24 ahead), as approved.
- Note statistics: 4-head/3-tail frame skips → 30 ms guard zones and the neighbouring-note exclusion, as instructed.
- Boundary placement also gained: 24-frame minimum side, no fallback split, veto at 25 cents (all found by dev or unit-test evidence before the gate run).
- Gate: "every boundary within ±20 ms" → p95 ≤ 20 ms and max ≤ 100 ms, plus the note-mean gate, as instructed.

## Amendment 2 (2026-11-22, after the sealed gate run): short notes at the edges of a run

Reason: with the 24-frame minimum a first or last note under about 130 ms was not separated from its neighbour, and the tonic of a scale at 16th notes and 120 bpm lasts 125 ms. Instruction: notes of 100 ms or more at the start or end of a run must be separated.

- **Rule:** a side that touches the start of the run (the first note, no earlier boundary) or the end of the run (decided in the flush) needs only 12 frames (`kFitMinEdge`, 64 ms) instead of 24. The other side must still have 24. The split is accepted only if the model of the long side (constant, or constant plus sinusoid, as already fitted) extended over the short side misses its frames by at least 25 cents rms (`kFitMinStep`). A vibrato swing at the edge of a steady note is predicted by the sinusoid; a new note is not. The existing veto (level change under 25 cents or the wrong sign) still applies.
- **Last frames of a run:** the last 3 frames (the segmenter already trims them from the statistics) take no part in a fit and cannot propose a boundary. The first version of the rule, with a margin test against a no-step fit over the whole window instead of the extension test, produced 7 spurious 85 ms tail notes and one false split on the dev seeds: a single garbage pitch frame as the note dies away (for example −2400 cents) drags the Viterbi path to the lowest state in the final frame, and the relaxed rule accepted it. A regression test covers 1 to 3 stray frames of three sizes.
- **Tests (written first, failing 128 of 192 cases before the change, the 125 ms and 100 ms ones):** the first and last note of a run at 100, 125 and 150 ms, steps of 100 and 200 cents, vibrato 0 and ±30 cents at 5.5 Hz, 8 phases: two notes with the boundary within 20 ms.
- **Measured limits (dev-level sweep, 16 cases per cell, boundary within 20 ms):** steps of 100 cents or more with vibrato up to ±30 cents are separated at 100 ms and above (16/16); a 200 cent step at 90 ms and above even with ±50 cents of vibrato. A 100 cent step with ±50 cents of vibrato on both notes: 12/16 at 100 ms, 14/16 at 110 ms, 16/16 from 120 ms. Steps of 60 and 80 cents at a run edge are separated reliably only at about 110 ms and above for 80 cents without vibrato, and not reliably at 60 cents at any length tried: the emission cost (L1, 25 cents) is too small to pay the switching cost over so few frames. That is a limit of the HMM, not of the fit. (An earlier version of this line said it does not affect scale notes; that was wrong, see "Known limit: 60 to 80 cent steps in scale mode".)
- **Results:** unit tests 70 of 70; dev gates identical to before the amendment (recall and precision 1.000, 0 steady false splits, boundary error p95 14.1 ms and max 19.8 ms, note-mean error median 0.00 and max 1.48 cents, delay max 318 ms); C++ and Python agree on all 420 dev clips and on 1920 generated edge streams (0 count or frame mismatches, times and means within 1e-6); ASan and TSan pass.
- **Not done:** no sealed gate has been run on the amended version. The sealed seeds 31001 to 31004 stay spent. Certifying Amendment 2 needs a fresh sealed seed set, fixed before it is used.

## Amendment 3 (2026-11-22, after sealed set 2 failed): causes found on dev seeds

Set 2 was not inspected. The tail of the note-mean error was looked for on wider dev seeds that were never sealed (9103 to 9108, 900 clips, 1800 notes); the tail was there, with a maximum of 23.95 cents.

1. **Octave-error frames at the start of a run.** YIN returns an octave error for the first frames of a note (4 frames at −1200 cents in the worst clip). The HMM starts in the octave-down state; Amendment 2's short-edge rule then accepted a split about 85 ms into a steady vibrato note, and the first note's mean was off by 6.13 and 23.95 cents on two clips. Fix: leading frames (among the first 8 of a run) more than 600 cents from the median of the next 8 take no part in a fit. The pre-Amendment-2 binary had no such error on these two clips. Test: octave-error frames of three sizes and counts before steady notes with 0, ±25 and ±45 cents of vibrato.
2. **A search window longer than the data.** The boundary may lie up to 24 frames after the HMM's proposal (the Viterbi path switches early when the old note's vibrato reaches the new state), but with a lag of 40 frames only 13 of those candidates kept 24 frames on the right. A weak step (64 cents) under vibrato wider than the step was placed 70 ms early and the note mean was 2.08 cents off. Fix: the right side may have 12 to 23 frames for any candidate, with the same extension test as at a run edge (the model of the left side extended over it must miss it by 25 cents rms).
3. **A blind spot in the harness.** The count of spurious notes ignored any extra note starting within 150 ms of the true onset, which hid a fake note split off the start of the first note. It now allows 60 ms. Sets 1 and 2 were scored with the wide window. A fake start note also moves the first note's mean, so the note-mean gate would have shown a large one, but I cannot rule out smaller ones in set 1.

Results on dev after the three changes: 71 unit tests pass; dev seeds 9101 and 9102 identical to before (recall and precision 1.000, boundary error p95 14.1 and max 19.8 ms, note-mean error max 1.48 cents, delay max 318 ms); wider dev seeds 9103 to 9108: recall 900/900, 0 spurious notes, 0 steady false splits, boundary error p95 12.1 and max 20.2 ms, note-mean error median 0.00, p99 0.69, max 1.26 cents, delay max 329 ms (it grew from 318 ms because later candidates are now allowed; the limit is 350). C++ and Python agree on all 420 dev clips and on 1920 generated edge streams; ASan and TSan pass.

## Known limit: 60 to 80 cent steps in scale mode (to be closed in Phase 3)

Recorded 2026-11-22 at Kelechi's correction. A step of 60 to 80 cents next to a short note is not reliably separated, because the L1 emission cost (25 cent scale) cannot pay the switching cost of 24 over so few frames; at a run edge it was not reliable at 60 cents at any length tried. I had written that this does not affect scale notes. That was wrong: a student playing a semitone 30 cents flat produces a step of about 70 cents, and that is exactly the case a scale exercise exists to catch.

Closing it is a Phase 3 item, not built now: score-informed segmentation. In scale mode the expected next note is known, so the HMM gets a lower switching cost toward the expected next note (and the usual cost to any other state). That needs the scale mode and its note sequence, which do not exist before Phase 3. Until then a short note next to a 60 to 80 cent step may be merged with its neighbour; the note-level summary then reports the merged note, and nothing is invented.

## Consequences

- A note that ends with a pitch change is reported 213 ms plus the HMM's switch delay late (up to ~330 ms measured; the limit is 350). The UI shows the live display immediately and does not wait for notes; scale grading is not live.
- The note boundary no longer shares a code path with `is_onset`. The two can disagree (the onset flag fires 30 ms after a step, the note boundary later but timestamped at the step).
- The fit assumes at most one vibrato rate per side and 3.5–9 Hz. A sideways slide (portamento) is not a step and may be vetoed or placed at its steepest point.
- Known limits carried over: two same-pitch notes with no RMS rise are not split.

## Gate result: sealed set 1 (version before Amendment 2)

One run, 2026-11-22 09:29, frozen binary, sealed seeds 31001-31004 (600 step clips, 240 steady-vibrato clips, 1200 notes scored). No tuning against these seeds; the values are those frozen in this ADR. Logged in `tools/accuracy/reports/phase1/gate_runs.log`.

| Gate | Limit | Measured | |
|---|---|---|---|
| recall (steps >= 60 cents, vibrato to +-50 cents, 4-8 Hz) | >= 0.995 | 1.000 (600/600) | PASS |
| precision | >= 0.995 | 1.000 (0 spurious notes) | PASS |
| false splits, steady wide vibrato | 0 | 0 of 240 | PASS |
| boundary error p95 | <= 20 ms | 13.4 ms | PASS |
| boundary error max | <= 100 ms | 29.4 ms | PASS |
| note-mean error max | <= 2.0 cents | 1.81 cents | PASS |
| note-mean error median | <= 0.5 cents | 0.00 cents | PASS |
| summary delay max | <= 350 ms | 310 ms (median 235) | PASS |

Margins: the note-mean max (1.81 vs 2.0) and the delay max (310 vs 350) are the thin ones. The dev set gave 1.48 cents and 318 ms, so the sealed seeds were not easier. Limits that stood at the time of the run: a note under about 130 ms at the start or the very end of a run was not separated from its neighbour (changed by Amendment 2); two same-pitch notes with no RMS rise are not split; results are glibc only until ADR 0005 is decided and run.

## Gate result: sealed set 2 (version with Amendment 2): FAILED

Pre-registered before the run in `tools/accuracy/reports/phase1/sealed_set_2.md` (seeds 32001 to 32004, hash of the seed list, hash of the frozen binary and of the sources). One run, 2026-11-22 10:20, frozen binary `/tmp/frozen/intono-cli-gate2` (sha256 720b9a11...). 600 step clips, 240 steady-vibrato clips, 1200 notes scored.

| Gate | Limit | Measured | |
|---|---|---|---|
| recall | >= 0.995 | 1.000 (600/600; every bucket 1.000) | PASS |
| precision | >= 0.995 | 1.000 (0 spurious notes) | PASS |
| false splits, steady wide vibrato | 0 | 0 of 240 | PASS |
| boundary error p95 | <= 20 ms | 13.6 ms | PASS |
| boundary error max | <= 100 ms | 20.2 ms | PASS |
| note-mean error max | <= 2.0 cents | **2.32 cents** | **FAIL** |
| note-mean error median | <= 0.5 cents | 0.00 cents | PASS |
| summary delay max | <= 350 ms | 325 ms | PASS |

Reported as measured: the gate failed on one number. The p95 of the note-mean error is 0.50 cents and the median 0.00, so the failure is a tail of a few notes, not a general bias. Set 1 gave a maximum of 1.81 and the dev seeds 1.48, so the margin was thin and the tail was longer on fresh clips, as the earlier "thin margins" remark in the first gate result said it could be.

What this does not tell: whether Amendment 2 caused it. The base design was not run on set 2, and cannot be (the set is spent), so the cause is open until it is found on dev data. No clip of set 2 was inspected and nothing was tuned against it.

Next, as agreed: find the cause on dev seeds (wider dev population than 9101 and 9102, which never produced a tail this long), fix, and register a fresh sealed set before any new gate run. Set 2 is never reused.

## Gate result: sealed set 3 (version with Amendments 2 and 3): PASSED

Pre-registered before the run in `tools/accuracy/reports/phase1/sealed_set_3.md` (seeds 33001 to 33004, seed-list hash, frozen binary hash and source hashes; copy in the Project store). One run, 2026-11-22 10:35, frozen binary `/tmp/frozen/intono-cli-gate3`. 600 step clips, 240 steady-vibrato clips, 1200 notes scored. No tuning against this set; no clip of it was inspected.

| Gate | Limit | Measured | |
|---|---|---|---|
| recall (steps >= 60 cents, vibrato to ±50 cents, 4 to 8 Hz) | >= 0.995 | 1.000 (600/600) | PASS |
| precision (spurious-note window at the start of a run now 60 ms) | >= 0.995 | 1.000 (0 spurious notes) | PASS |
| false splits, steady wide vibrato | 0 | 0 of 240 | PASS |
| boundary error p95 | <= 20 ms | 13.0 ms | PASS |
| boundary error max | <= 100 ms | 20.0 ms | PASS |
| note-mean error max | <= 2.0 cents | 1.02 cents | PASS |
| note-mean error median | <= 0.5 cents | 0.00 cents | PASS |
| summary delay max | <= 350 ms | 330 ms (median 235) | PASS |

Margins: the delay maximum (330 against 350 ms) is now the thin one; it grew from 310 ms (set 1) because Amendment 3 lets later boundary candidates through. The note-mean maximum has room (1.02 against 2.0). Three sealed sets have now been used for one design: the first passed the base design, the second failed, the third passed; the first and third are the evidence, and the sets are synthetic audio from the same generator, so they say little about real violins.

## Freeze on synthetic data (2026-11-22, Kelechi)

DSP tuning on synthetic audio stops here; the code is tagged `dsp-v0.1-synthetic`. From now on the DSP changes only in response to real-audio results or CI failures, each recorded in an ADR amendment with the evidence. The 350 ms summary-delay gate stays; if real audio pushes the delay over it, 400 ms will be considered then, by ADR, not before. Sealed sets 1 to 3 are spent; any later gate needs a new pre-registered set.

## Real clip #1 findings: a short middle note is lost (2026-11-22, diagnosis only; the freeze stands)

Observed: in a fast descending scale on clip #1 (notes of 140-240 ms), the descending E4 (145 ms) and D4 (140 ms) came out as one note.

Not the cause: the 64 ms bow dropout between them, the 18 dB level dip, bow noise or an unvoiced frame. YIN tracks both notes cleanly (329 Hz, then 293 Hz after 11 unvoiced frames), the note HMM switches label at exactly the right frame (it ignores unvoiced frames), and a synthetic legato run with no dropout fails the same way.

Cause: the change-point fit (a) assumes a single boundary inside its window and (b) refuses candidates whose left side has fewer than kFitMinSide (24) usable frames once a run is under way (the first 3 frames of a note are trimmed). The E4 has 23 usable frames, so the true boundary is never a candidate, and the fit picks the next boundary (D4 to C4, 40 frames of look-ahead later). Every earlier synthetic boundary test had one step per clip or notes of 0.4 s and more, so two boundaries never fell inside one look-ahead window and a note under about 27 voiced frames (about 145 ms) never had to serve as the left side in mid-run.

Evidence: replaying the Python mirror on the real extract and on synthetic E4-D4-C4 legato runs, a smaller left-side minimum recovers the note (offline probe only; two synthetic seeds out of three recovered at 20 frames, a different misplacement appears on the third). That is a diagnosis, not a tuned fix; nothing in the engine changed.

New synthetic case (generator only): `build_short_run_set` in tools/accuracy/ref/synth.py (runs of 5-7 legato notes of 110-250 ms, steps of 1-3 semitones, a third of the phrases with a 30-70 ms bow dropout), evaluated by tools/accuracy/run_short_runs.py (dev seeds 9xxx only). Baseline of the frozen engine on dev seed 9301: 145 of 181 notes recovered (recall 0.801), 12 extra notes; misses by note duration: under 150 ms 19 of 33, 150-200 ms 11 of 45, 200 ms and over 6 of 103.

Fix: not proposed yet. Candidate directions for a later amendment: a multi-boundary fit, or a left-side minimum that depends on the committed note's length. It is a DSP change, so it needs your go-ahead (freeze rule: real-audio result, which this is) and parameters chosen on dev data only.

## Amendment 4 (2026-11-22, after real clip #1): boundaries between short notes, anchored on the HMM's switches

Status: implemented; passed its sealed short-run set and the ADR 0004 boundary set 4 (results below). Reason: on clip #1 the E4 and D4 of a fast scale were one note (section "Real clip #1 findings"). Instruction (Kelechi, 21:04): multi-boundary; the HMM switch frames are the anchors; each boundary is refined only inside the window bounded by its neighbouring switches, so no window holds two boundaries; a side too short to fit gets the existing "the long side must not explain it" test, or the HMM's switch frame is kept; no length-dependent minimum. Gates: short-run recall >= 0.995 for notes of 150 ms and more and >= 0.98 for 100 to 150 ms; at most 1 extra note per 200; every ADR 0004 gate still passes. Tune on dev seeds only, register a fresh sealed short-run set, run it once. Clip #1 is a check, never tuning data.

### What changed (dsp/src/notes_hmm.hpp, mirrored in ref/stream_ref.py)

1. **Anchored windows.** At a label change at frame k the fit looks at the current best path for the next switch kn after k. The fit's data end at kn - 1 (before: `last`, 40 frames after k), so a window holds at most the boundary it is placing. The previous boundary was already placed, and the data start after it (as before). The path is decoded backwards, so its switch frames sit on the steps; no margin is kept before kn.
2. **Side minimum.** A side needs kFitMinEdge (12) frames, the same constant as at a run edge and the minimum note length, not a new number and not a function of the note's length. A side of 12 to 23 frames is accepted with the existing extension test (the long side's model, extended over it, must miss it by 25 cents rms). Before: 24 frames on the left once a run was under way.
3. **Keep the HMM's frame.** If neither side reaches 24 frames (two short notes side by side), the fit is not run: the boundary is the HMM's switch frame, provided the medians of the frames on each side differ by 25 cents in the direction of the change (the old veto). The same fallback applies if, after the smeared frames are taken out, every candidate has two short sides and the extension test rejected none. If the extension test rejected a candidate there is no boundary (a vibrato swing at an edge stays one note).
4. **Transient dwells (not in the instruction; needed).** YIN's octave errors at the head of a note appear in the Viterbi path as a dwell of a few frames in another state. Before, that made two proposals: into the octave-down state (right side of 3 frames, no valid fit, so no boundary) and out of it, which was then compared with the glitch state, not the note before it, so a real step was read as a change in the wrong direction and vetoed. A dwell shorter than kFitMinEdge frames before the next switch is not a note (the segmenter discards notes under 10 frames anyway): it makes no proposal, the next switch is compared with the note before the dwell, the boundary is the dwell's first frame (the dwell starts at the step), and the dwell frames fall in the new note's guard zone. A dwell that returns to the same state makes no boundary at all (an octave glitch inside a steady note used to split it).

   Deviation to flag: the first version searched candidates in the transient case too (latest one within the BIC tie). On clip #1 that placed a real 200-cent step 90 ms early at 13.9 s, because the old note drifts by about 10 cents and its cost grows smoothly with the candidate; nothing on the right constrains it. Searching was removed and the HMM's frame kept. No constant was tuned; the synthetic dev results are identical before and after (below). This means clip #1 is no longer an untouched check for that boundary.

### Gate scope: the HMM limit is wider than 60 to 80 cents

Most of the misses left on dev are notes the HMM never visits: a note whose centre is within about 100 to 150 cents of its neighbours is cheap to explain by a neighbour's state (the emission is flat within 50 cents, and detune moves the note toward the neighbour), so two switches (cost 48) never pay. That is the same mechanism as the recorded 60 to 80 cent limit, and it reaches further for short notes. Measured (eight dev seeds, steps drawn down to 100 cents, 1089 interior notes): smaller adjacent step 100 to 130 cents: 51 of 472 notes missed; 130 to 160, 160 to 200 and 200 and over: 0 of 509. With the step limit at 130 cents on four other dev seeds, 3 notes with steps of 134 to 146 cents under vibrato were skipped. The short-run set therefore has a centre step of at least **150 cents** (the generator redraws the detune), and the 60 to 150 cent range is not in this amendment's gate: it needs the Phase 3 score-informed segmentation, as already recorded. This is a scope decision I made from dev evidence; Kelechi approved it before the sealed run (2026-11-22) and asked for the 100 to 150 cent band to be reported as informational.

### Dev evidence

- Short-run set (`ref/synth.py: build_short_run_set`, runs of 5 to 7 legato notes of 100 to 250 ms, steps 150 to 300+ cents, a third with a 30 to 70 ms bow dropout, half the notes with vibrato of +-15 to +-30 cents at 5 to 7 Hz; `run_short_runs.py`). Frozen binary on seeds 9301 to 9304 (before the scope/vibrato changes, steps of at least 100 cents): recall 0.794, 17.7 extra notes per 200. New binary, steps of at least 150 cents: seeds 9301 to 9308 (used while designing): 1427 of 1428 notes (100 to 150 ms: 326 of 327; 150 ms and more: all 1101), 0.14 extra per 200. Seeds 9309 to 9312 (looked at only after the design was settled): 722 of 722, 0 extra.
- ADR 0004 dev gates, seeds 9101 to 9108 (1200 step clips, 480 steady): recall 1200/1200, 0 spurious, 0 steady false splits, boundary error p95 11.8 ms / max 20.2 ms, note-mean error median 0.00 / p99 0.74 / max 1.48 cents, delay max 329 ms. Identical to the frozen version except p95 12.1 to 11.8 ms.
- Tests: 74 pass (71 before, 3 new in test_notes.cpp: runs of five notes with the middle three 100 to 170 ms, 160 cases; octave-error dwells in the middle of a run; a brief octave dwell inside a steady note). On the frozen tracker the first fails 160 of 160 and the third fails; the second passes (it does not separate the two versions; kept as a regression test). C++ and Python agree note for note on 420 dev clips, 300 short-run phrases and 1920 edge streams (0 mismatches); ASan/UBSan and TSan pass on the unit tests.
- Clip #1, check only (real, internal): E4 and D4 are separate notes (30.87 s and 31.06 s, 1.5 and 1.9 cents sd), the 13.9 s boundary is at 13.949 s (pYIN: 13.95 s). 42 of 47 old notes are unchanged in pitch and start (within 150 ms); the rest are in the speech region and the octave-error episodes, which this amendment does not touch (A3 is still reported as an octave error). Boundary times against pYIN steps: median 31 ms before, 28 ms now.

### Sealed results (2026-11-22, one run each, frozen binary `/tmp/frozen/intono-cli-gate4` sha256 0396631400...; no tuning, no clip inspected)

**Short-run set, seeds 34001 to 34008 (gated; centre steps >= 150 cents; scope approved by Kelechi):** 1449 of 1449 notes recovered, 0 extra notes. PASS on all three gates.

| Gate | Limit | Measured | |
|---|---|---|---|
| recall, notes >= 150 ms | >= 0.995 | 1.000 (1138/1138) | PASS |
| recall, notes 100 to 150 ms | >= 0.98 | 1.000 (311/311) | PASS |
| extra notes per 200 | <= 1 | 0.00 | PASS |

**ADR 0004 boundary set 4, seeds 35001 to 35004 (original gates):** PASS on all eight gates.

| Gate | Limit | Measured | |
|---|---|---|---|
| recall / precision | >= 0.995 | 1.000 / 1.000 (0 spurious) | PASS |
| false splits, steady wide vibrato | 0 | 0 of 240 | PASS |
| boundary error p95 / max | <= 20 / <= 100 ms | 12.3 / 21.0 ms | PASS |
| note-mean error max / median | <= 2.0 / <= 0.5 cents | 1.16 / 0.00 cents | PASS |
| summary delay max | <= 350 ms | 312 ms (median 235) | PASS |

**Informational, no gate: short-run set with steps down to 100 cents, seeds 34101 to 34108** (a separate set run once, because the gated clips contain no step under 150 cents): 1385 of 1433 notes recovered (0.967), 16 extra notes (2.23 per 200). By the smaller centre step to a neighbour:

| Smaller adjacent centre step | Notes | Missed | Recall |
|---|---|---|---|
| 100 to 130 cents | 594 | 45 | 0.924 |
| 130 to 150 cents | 94 | 2 | 0.979 |
| 150 cents and over | 745 | 1 | 0.999 |

By duration: 100 to 150 ms 0.900, 150 to 200 ms 0.987, 200 ms and over 0.984 (the misses sit in the 100 to 130 cent band, not in the length). This matches the dev finding: the HMM is reliable from about 150 cents and loses about 1 in 13 notes at a semitone.

### HARD Phase 3 gate: semitone steps in short notes (Kelechi, 2026-11-22)

Steps of 100 to 150 cents (a semitone in tune, or a semitone played flat or sharp) between short notes are the most common step in a scale, and the engine misses 7.6% of them (informational result above). Score-informed segmentation (lower switching cost toward the expected next note in scale mode, see "Known limit") must reach **recall >= 0.995 on notes of 100 to 250 ms with a smaller adjacent centre step of 100 to 150 cents, in scale mode, on a fresh sealed set**, before Phase 3 can close. This is a gate, not a goal: Phase 3 does not close without it. Its generator exists (`build_short_run_set(..., min_step_c=100.0)`); the sealed set will be registered before the Phase 3 implementation is run against it. Recorded in `phase-3-plan.md` in the Project store.

### Glitch rule (item 4): accepted on two conditions

Kelechi accepted the 12-frame transient-dwell rule on 2026-11-22 on two conditions:

1. **A test that a real 80 to 90 ms note inside a fast run survives.** Added (`ARealNoteOf80To90MsInsideAFastRunSurvivesTheGlitchRule`, 108 cases: middle note 80, 85 and 90 ms between 140 ms notes, three step patterns, vibrato 0 and +-25 cents, with and without 2 octave-error frames at its head): passes. A fourth step pattern (-200, -300, -150, -200 cents with vibrato) loses the note in 4 of 36 cases. Switching the rule off does not fix them (it fixes none of the four and loses 73 of 144 in all), so I do not think the rule causes them; the likely cause is the HMM limit at a 150-cent neighbour on a note under the 100 ms gate. That is not isolated. The cases are kept as a disabled test (`DISABLED_ShortNoteNextToA150CentStepWithVibratoKnownLimit`) that has to pass before Phase 3 closes. 75 tests pass, 1 disabled.
2. **Revisit when ADR 0007 lands.** The rule exists because YIN's octave errors reach the Viterbi path as a dwell of a few frames. If ADR 0007's multi-candidate tracking removes those errors upstream, the rule may be unnecessary and should then be removed or re-justified with evidence (ADR 0007 carries the same item).

## Amendment 5 (Kelechi, 2026-11-28): the 80 to 90 ms note next to a 150-cent step stays a documented free-mode limit

Condition 1 above asked for `DISABLED_ShortNoteNextToA150CentStepWithVibratoKnownLimit` to pass before Phase 3 closes. Kelechi re-scoped
it on 2026-11-28, with no DSP change:

- **Scale mode meets the requirement.** The same cases pass there: `ShortNoteNextToA150CentStepWithVibratoInScaleMode`, 36 of 36,
  using ADR 0014's score-informed segmentation.
  - On the sealed set p3gate, recall on 100 to 250 ms notes next to a 100 to 150 cent step was 1.0000, on 1087 notes
    (`tools/accuracy/reports/phase3/sealed_p3.md`).
- **In free mode it is a documented limit.** Free mode has no score to lean on. With steps of −200, −300, −150 and −200 cents and
  vibrato of ±25 cents, 4 of the 36 cases lose the 80 to 90 ms note. That note is below the 100 ms gate, next to a 150-cent neighbour.
  - The free-mode test stays disabled, as the record of that limit. Its comment points here.
  - Free mode stays byte-identical to `phase1-complete` (golden manifest).
- **Condition 2 (revisit the 12-frame rule after ADR 0007) stays open** until ADR 0007 is implemented (Kelechi, 2026-11-28).
- **The other Phase 3 known limit, 60 to 80 cent steps (the section above), measured on dev seeds only (2026-11-28).** The sealed set
  p3gate covered steps of 100 to 150 cents, not this case. Setup: dev seeds 9501 to 9516, `build_short_run_set(seed,
  min_step_c=60)`, notes of 100 to 250 ms, the frozen binary `fc29130`.

  | Smaller neighbour step | Notes | Free mode | Scale mode |
  |---|---|---|---|
  | 60 to 80 cents | 250 | 0.824 | **0.996** |
  | 80 to 100 cents | 320 | 0.850 | **1.000** |
  | 100 to 150 cents | 471 | 0.955 | **1.000** |

  - Scale mode closes this case in practice.
  - In free mode it stays a documented limit, like the one above.
  - No sealed gate was registered for it. If Kelechi wants a hard number here, it needs its own pre-registered set.
