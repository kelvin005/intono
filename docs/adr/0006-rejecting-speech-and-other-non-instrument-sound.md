# ADR 0006: Rejecting speech and other non-instrument sound

Status: Proposed (2026-11-22, design and data plan complete; design approved by Kelechi 2026-11-23 12:17; decisions 1 to 6 approved 2026-11-22 21:58; G5 and G8 corrected 2026-11-23; the scripts are written, the DSP change waits for the data). Nothing is implemented, no dataset is in, and no feature, weight or threshold has been looked at. Phase 2 stays on hold. DSP is frozen on synthetic data (ADR 0004); this is a response to a real-audio result, so it may propose a change, with the evidence below.

## Context

Real-audio clip #1 (a third-party phone tutorial, kept in the gitignored `testdata/real/`, never committed; measurements in `reports/real-audio-clip-1.md`) has 11.6 s of speech in five regions. The frozen engine, run on it with `--notes 1`:

- emitted **13 notes in the speech regions** (5, 2, 2, 3 and 1 per region) from 369 voiced frames, 18 % of the speech frames, about 2.0 s. The ADR 0001 display path would have moved the needle on those frames too.
- The speech notes are short (52 to 342 ms), with a median YIN confidence of 0.948 against 0.996 on the scale notes, but 0.91 to 0.96 per note is not far from the quietest real notes (a 75 ms B3: 0.94; the octave-error notes: 0.94). A fixed confidence threshold sits close to real notes.
- Per-hop pitch change of the voiced frames: median 2.1 cents (p90 10) in speech, 0.1 cents (p90 0) in the scale notes. Voiced runs: median 29 ms (max 331 ms) in speech, median 203 ms in the scale. One clip, one speaker, one phone: these show that signals exist; they are not thresholds.
- pYIN marks 75 % of the same speech frames voiced, so the problem is not specific to this engine: pitch trackers detect pitch, and speech has pitch.

The synthetic tests have no speech, so no sealed set could have shown this. Voice is a normal condition for a tutorial, a lesson recording and a teacher in the room: a Phase 1 gap, not an edge case.

## What has to be true of a solution

1. Speech between notes produces no notes and does not move the display needle.
2. Violin notes are not lost: soft playing, sul ponticello, harmonics, very low notes (G3), short notes of 75 ms, pizzicato, scratchy bow starts. Losing a real note is worse than keeping a speech note: a student blames the app for the first and ignores the second.
3. Causal and cheap: no look-ahead beyond what the pipeline already has, a few microseconds per hop (the whole engine is 14 to 17 us per 5333 us hop), all memory preallocated, RT-safe, no audio stored or sent anywhere.
4. Few parameters, chosen on development data that is not the clips used to report results.

## Options considered

- **A. Note-level filter only.** Drop a note after it closes if its statistics look like speech. Smallest change; the display still follows speech. It is the **baseline B must beat**.
- **B. Frame-level instrument score with hysteresis, plus a run-level decision for note summaries (recommended; designed below).**
- **C. A small learned classifier** (cepstral coefficients or the same features, a tiny network). Likely the most accurate; brings a model to train, version and ship, and the largest overfitting risk. Only if B fails on development data (trigger below); it would need its own ADR.
- **D. Mute at the app level** (quiet room, push to talk). Nothing to test; the lesson-recording use case stays broken. Rejected.

## Decision proposed: B

### Where it sits

`YIN -> guard (ADR 0003) -> instrument score -> is_voiced with hysteresis -> display (ADR 0001), onset flag, note HMM (ADR 0004)`.
`intono.h` does not change: `is_voiced` keeps its meaning (pitched instrument present). An exposed score would be an API change and needs its own ADR. The score is computed from each voiced hop and from data of the last N hops only (causal).

1. **Live path (display and `is_voiced`).** The score `s_t` is compared with two thresholds, `theta_hi` and `theta_lo`. A frame becomes voiced after `N_on` consecutive hops with `s >= theta_hi`; it stays voiced until `N_off` consecutive hops with `s < theta_lo`. Frames before acceptance are not retro-displayed (the display is live), but see item 2.
2. **Note summaries (ADR 0004 path).** Notes already arrive 213 ms or more after the event. The decision for note summaries is made on the whole run with that delay for free: the frames held back by `N_on` are kept in the note when the run is accepted (the run start is the first voiced-by-YIN frame, not the accepted frame), and a closed note is **dropped if the median score of its frames is below `theta_lo`** (no extra parameter). The note start time therefore does not move, and the 350 ms delay gate is unaffected.
3. **Interaction with the note HMM.** A rejected stretch is an unvoiced gap: up to 20 hops are skipped inside a run; longer ends the run (ADR 0004, unchanged). A falsely rejected piece of a real note therefore costs at most a gap or a split, which the gates below count.
4. **Interaction with ADR 0007.** An octave-up error reports 2 f0; a comb at 2 f0 sees only the even harmonics, so harmonicity can drop on exactly the frames that are already wrong, and a long episode (357 ms in clip #1) could take the whole note with it. Every harmonic feature is therefore computed at the reported f0 and at f0/2, keeping the better value. Losing wrong frames is not a loss; losing the right note around them is, and the gates measure it. The glitch rule of ADR 0004 (item 4 of Amendment 4) and ADR 0007's multi-candidate tracking must be re-checked together with this change.

### Candidate features (declared now, before any measurement)

All are computed from the raw guarded pitch and the spectrum of the current window, using only the band **below 5 kHz**. Reason: every candidate corpus is 16 kHz (NSynth, LibriSpeech, speechocean762, MUSAN), so it has nothing above 8 kHz, while the phone clips have it. A feature that used the full band would learn "has high-frequency content" and fail on real audio in the opposite direction. The check for this is in the protocol (item 6, "bandwidth check").

| ID | Feature | Rationale | Cost |
|---|---|---|---|
| F1 | YIN confidence, `1 - d'(tau)` | already computed; weak alone (clip #1: 0.948 vs 0.996, overlap with soft notes) | 0 |
| F2 | Harmonic comb ratio: energy within +-0.25 f0 of k f0 (k = 1..8, below 5 kHz) over energy in the band up to 8 f0, from a Hann window FFT of the guarded frame, at f0 and f0/2 | bowed string: strongly harmonic, smooth falloff; speech is breathier | one FFT per hop (reuse of YIN's pffft spectrum to be measured; the window is 1024 samples at 48 kHz, 47 Hz per bin, so G3 at 196 Hz has about 4 bins between harmonics: a 2048-sample transform may be needed for this feature alone) |
| F3 | Harmonic amplitude regularity: standard deviation of the second difference of log harmonic amplitudes, k = 1..8 | formants make the amplitudes irregular; a string's are smooth | from F2's spectrum |
| F4 | Spectral centroid below 5 kHz divided by f0 | speech centroid moves with the vowel; violin has a fixed ratio per register | from F2's spectrum |
| F5 | Pitch stability: fraction of the last N hops with `|delta ctr| < 8 cents` per hop, where `ctr` is the ADR 0001 vibrato centre (so vibrato does not count against it); and the fraction with a constant-sign slope for a portamento | clip #1: median 2.1 cents per hop in speech vs 0.1 in notes; vibrato and portamento are allowed through because the centre is used | 0 (existing data) |
| F6 | Voiced fraction of the last 20 hops (flutter) | speech runs are short (median 29 ms in clip #1); this is the hysteresis information as a feature | 0 |
| F7 | RMS modulation depth over the last 1 s (3 to 8 Hz band of the log RMS) | syllables modulate level by 10 to 20 dB; a held note does not; bow changes and vibrato modulate a little | 0 (RMS exists) |

Features that need the full band, a learned embedding, or any look-ahead are not candidates.

### The model and the number budget

The score is a logistic function of **at most 4** of the features above (standardised with fixed constants), with fixed L2 = 1.0:

`s = sigmoid(b + w1 f1 + ... + w4 f4)`.

Free numbers, all of them (this replaces the earlier "about six numbers"; with a learned score that is not achievable honestly, decision 1 below): up to 4 weights and 1 bias (5), `theta_hi`, `theta_lo`, `N_on`, `N_off`, and the stability window `N` (5): **at most 10**. Nothing else is fitted. Fixed in advance and not tuned: the 5 kHz band limit, 8 harmonics, the 8-cent per-hop limit in F5 (a first value, changed only by amendment with dev evidence), L2 = 1.0.

**Selection rule, fixed now.** Forward selection from the empty model over F1..F7: a feature is added if it lowers the pooled leave-one-group-out balanced log-loss by at least 2 % (relative) and the total stays at 4 features. Groups are speakers for speech and instruments for violin (see protocol). Then, on development data only: `N_on` from {2, 3, 4, 6} and `N_off` from {3, 6, 10}; `theta_lo` = the lowest value for which violin frames lost are at most 0.2 % (half of the 0.5 % gate), `theta_hi` = the lowest value for which speech notes are at most 0.25 per minute on held-out speakers (half of the 0.5 gate). If no `theta_hi >= theta_lo` satisfies both, B has failed on development and nothing sealed is run: the trigger for C.

## Data plan

Test only. No dataset audio is committed, shipped or put in the Project store; all of it lives in the gitignored `testdata/public/` (to be added to `.gitignore` when the first dataset arrives). The downloads are blocked from this workspace (the proxy refuses openslr.org and storage.googleapis.com), so **Kelechi uploads the files**. The numbers that ship, if B is approved (a handful of weights and thresholds), are derived from the data; the data does not ship. A `docs/THIRD_PARTY_DATA.md` with the citations and licences is kept anyway (decision 6).

| Corpus | Licence (as stated by the source) | Use | Notes that matter |
|---|---|---|---|
| NSynth, test split (Magenta) | CC BY 4.0 | violin-like material: `instrument_family = string`, `instrument_source = acoustic` (also `vocal`, acoustic, as an informational sung-vowel class) | 4 s notes at 16 kHz (held 3 s, decay 1 s), sample-library instruments, labelled by family and quality, **not by instrument name**: it is acoustic strings (violin, viola, cello, bass, pizzicato), not a violin corpus. The test split has few instruments (to be counted on arrival); if too few to leave out one at a time, ask for the validation split (12,678 notes) too |
| LibriSpeech test-clean | CC BY 4.0 | adult native read speech; 40 speakers; speaker-held-out splits | 16 kHz |
| speechocean762 (OpenSLR SLR101) | CC BY 4.0 on OpenSLR (the Hugging Face mirrors say Apache 2.0; the original source is the one used here) | children's and adult speech: 5000 sentences, 250 speakers, half children, all Mandarin-speaking non-native English, recorded on phones | 16 kHz; speaker age and gender from the corpus metadata are needed to separate children from adults. Children's f0 reaches the violin range, so pitch range cannot help: this is the likely hardest case |
| MUSAN (OpenSLR SLR17), noise part only, optional | CC BY 4.0 overall; every subdirectory has a LICENSE file connecting each wav to its own licence | room and background noise for the mixtures | A file is used only if its LICENSE entry is present and allows commercial use; each used file and its licence string go in the manifest. Its speech part (LibriVox) and music part are not used. Mixing is a derivative: used for internal testing only, never redistributed |

**Resampling and band.** All four are 16 kHz; the engine runs at 44.1 and 48 kHz. Audio is resampled up with a fixed high-quality resampler (soxr, if present, else scipy polyphase) and carries nothing above 8 kHz. Design consequence: features use only below 5 kHz. Protocol item 6 checks it on real clips.

**Phone conditions, generated, not downloaded**: AAC at 64 kbps and Opus at 24 kbps through ffmpeg if installed (clip #1 is AAC); random frequency response (a few dB, band-limited like a phone microphone); synthetic room reverberation (exponential decay, T60 0.2 to 0.8 s: no external impulse responses); MUSAN noise or synthetic pink noise at 10 to 30 dB SNR; gain, clipping at 0 to 3 dB over.

**Not used**: no violin-and-voice mixtures from the web, no copyrighted tutorials beyond clip #1 (internal, check only), no singing corpora (decision 3).

## Splits (fixed now, before the data is looked at)

- **Held-out groups, deterministic.** Speakers (LibriSpeech id, speechocean762 id) and NSynth instruments are ranked by `sha256("intono-voice-1:" + id)` within their stratum (LibriSpeech: female / male; speechocean762: child / adult x female / male; NSynth: string-acoustic instrument id). The lowest 25 % of each stratum form the **sealed** pool, the rest the **dev** pool. Nobody looks at sealed-pool files before the sealed run, and dev-pool results never include them.
- **Leave-one-group-out (dev).** Speech: leave one speaker out, fit on the rest, score the left-out speaker; violin: leave one instrument out. Also **leave-one-corpus-out**: fit on LibriSpeech and MUSAN-free speech, test on speechocean762 children and adults. A number that works for one voice, one instrument or one corpus only is visible.
- **Real clips (Kelechi).** About 15: about 7 real dev (tune and check), about 8 real sealed (run once); at least 4 of the real clips recorded with a violinist on different phones, the rest internal tutorials. **Each real set (dev and sealed) must contain at least 10 minutes of playing and at least 4 minutes of speech**, and Kelechi records to that spec, including clips with speech over playing (layout d of the generator, for real). If a set falls short, its speech-note gate is reported but carries no weight and the synthetic-mixture gate decides.
- **Seeds.** Dev mixtures 9401 to 9412; sealed mixtures 44001 to 44004, registered with their hash and the frozen binary before the run, like the earlier sealed sets (to be confirmed unused at registration: 9101-9108, 9301-9312, 31001-35004 and 34101-34108 are taken).

## Mixture generator (specified now, written on approval)

Fixed seed per set, from the pools above only.

- **Violin phrases:** 3 to 8 NSynth acoustic-string notes (truncated at 0.1 to 1.5 s with a 20 ms fade-out, gaps 0.05 to 0.4 s, 10 ms crossfade where legato, pitch G3 and up, all velocity classes, `fast_decay` pizzicato included), placed with known onsets and offsets. This is crude legato; real bowing is covered only by the real clips.
- **Speech:** utterances from the pools, leading and trailing silence trimmed by an energy threshold; the whole utterance counts as speech, pauses inside it included (conservative for the speech-note count).
- **Layouts:** (a) speech only; (b) speech between phrases, no overlap; (c) speech starting within the last 300 ms of a note, and speech overlapping a note's first 300 ms; (d) violin and speech together at violin-over-speech levels +20, +10, +6, 0, -6 dB (the teacher who plays and talks).
- **Conditions:** each layout under clean, room noise (10 to 30 dB), reverberation, AAC, Opus, and combinations; the lead-in is 0.5 s of room noise (nominal) or none (clip #1 starts with speech: the noise gate learns its floor from the first 0.5 s, which clip #1 shows can be speech; reported separately, not gated, and opened as its own item if it matters).
- **Truth:** note times from the placement; speech intervals from the placement; pitch truth is not needed (comparison is against the frozen engine).

## Gates (proposed now so they cannot move afterwards; every gate is measured and reported on every run, passing or not)

Scoring: "found by the frozen engine" is the base. The frozen engine (`dsp-v0.1-synthetic`, ADR 0004 Amendment 4 build) is run on the same input; what is gated is what the change loses or removes, so the gate does not mix in detection errors that already exist (octave errors, same-pitch splits).

| # | Gate | Limit | Measured on |
|---|---|---|---|
| G1 | Speech notes (engine notes whose middle falls in a speech-only interval) per minute of speech | <= 0.5 per minute **in each of three groups**: LibriSpeech adults, speechocean762 adults, speechocean762 children | held-out speakers (leave-one-out), layouts (a) and (b); sealed: layouts built from the sealed pool |
| G2 | Speech frames with `is_voiced` true (needle moves) | <= 5 % per group (clip #1 now: 18 %; pYIN: 75 %) | same |
| G3 | Violin note recall relative to the frozen engine: notes the new engine reports / notes the frozen engine reports (same MIDI number, start within 80 ms) | >= 0.995 overall and in every condition: soft (velocity classes), low (G3 to B3), high (above E6), short (truncated to 75 and 100 ms), pizzicato, clean/noisy/reverb/AAC/Opus | NSynth acoustic strings (leave-one-instrument-out); real dev clips: the non-speech notes of the frozen run that pYIN confirms |
| G4 | Violin frames switched off | <= 0.5 % of the frames the frozen engine marks voiced in violin-only material (frames in the first `N_on` hops after a pause are counted in G5, not here) | same |
| G5 | Added acceptance delay of the display after a violin **onset** (Kelechi, 2026-11-23) | **<= 30 ms** (6 hops) at the maximum over onsets. Applies to onsets only: display latency during a sustained note keeps the existing target of **p95 < 50 ms** (unchanged, re-measured with the change) | same |
| G6 | Overlap: violin note recall relative to the frozen engine with speech over it | >= 0.98 at violin-over-speech +6 dB and above; reported, no gate, at 0 and -6 dB | layout (c) and (d) |
| G7 | No regression on synthetic input | on the synthetic dev clips (seeds 9101 to 9108, 9301 to 9312) the note lists are **identical** to the frozen engine's (same notes, same starts within one hop); otherwise ADR 0004 is re-certified on a new sealed set before this change is accepted (the 35xxx sets are spent). All unit tests pass | dev seeds |
| G8 | Cost and safety (Kelechi, 2026-11-22, corrected 2026-11-23) | **voice rejection: mean <= 50 us per hop** (with and without the feature, difference of means). **Real-time safety is about the worst hop:** the audio thread's worst hop, whole `intono_process`, **<= 100 us on desktop** (intrinsic: minimum over >= 10 runs of the same hop, pinned core), voice rejection included. The earlier "whole engine mean <= 100 us" reading was wrong and is withdrawn. The engine as first measured failed the worst-hop cap (about 210 us); ADR 0008 (implemented 2026-11-23) found most of that was denormal floating-point arithmetic in the decaying tail after a note, fixed it, and moved the HMM and the change-point fit (73 to 100 us worst hop when run inline on ordinary input) to a worker thread. The audio thread's worst hop is now 21 to 24 us (ADR 0008 results), which leaves room for this change's own cost. ASan/UBSan, TSan and the RT-safety binary clean; memory preallocated | `tools/bench/worst_hop` on the Linux Release build. Android factor: measured on a low-end phone in Phase 2 (ADR 0008 M5); no estimate is used as evidence |
| G9 | Real sealed clips | speech notes <= 0.5 per minute of speech and playing notes lost relative to the frozen engine <= 0.5 % (only if the sealed real set has at least 10 minutes of playing and 4 minutes of speech; otherwise reported, not weighted) | the sealed real set, once |
| G10 | Baselines | B must beat A (the same selection rule on note-level versions of the features, plus a plain confidence threshold) on G1 and G3 at equal G4, or A wins on simplicity; B's remaining justification then is G2 alone and is stated as such | dev |

**Informational classes, never gated:** NSynth vocal acoustic notes (sung vowels), humming and singing (decision 3), NSynth non-string acoustic families (flute, reed, brass, mallet), MUSAN noise alone (no notes should appear; reported).

**Adversarial cases written before the run** (all from the generator or the real clips): a student humming or singing the pitch; a teacher playing and talking together; violin with heavy bow noise (NSynth plus synthetic noise; the real clips for scratch); phone-compressed audio; a noisy room; speech with a long vowel on a steady pitch (the hardest false accept); a violin harmonic (high, nearly sinusoidal: F2 and F3 are weakest there, so the real clips matter; NSynth has no harmonics).

## Test protocol and the order of work on arrival ("runbook")

The scripts below are written (2026-11-23) in `tools/voice/` and plumbing-tested on generated stand-in corpora (`selftest.py`); they have not touched real data. Known gap: the option A note-level baseline is not yet in `eval_gates.py`. Their hashes go in the pre-registration. `tools/voice/README.md` has the commands. Data and results stay under `testdata/` and `tools/voice/` (code only in git).

0. **Intake (`tools/voice/intake.py`).** For each upload: record the sha256 of each archive; compare with the publisher's checksum where one is published; extract into its own empty directory under `testdata/public/<corpus>/`; copy the licence text into `LICENSE.txt` beside it; write `manifest.json` (file count, total seconds, sample rate, licence, source URL). Refuse an unexpected sample rate or channel count. Check the counts match the corpus description (LibriSpeech test-clean: 40 speakers; speechocean762: 250 speakers, 5000 utterances; NSynth test: 4096 notes). Fail loudly, fix nothing silently. Acceptance: manifest committed (no audio), counts reported.
1. **Pools (`pools.py`).** Apply the split rule above; write `pools.json` (ids only, plus its sha256). Print group sizes. Acceptance: sealed pool file is hashed and not opened again until the sealed run.
2. **Baselines on dev (frozen engine, no change).** Run the frozen binary on speech-only and violin-only dev material, all conditions: this reproduces the problem (expected: speech notes in the tens per minute, as in clip #1) and sets the G3/G4/G6 bases. Acceptance: the numbers are written to `reports/voice/baseline.md` before any feature is computed.
3. **Features (`features.py`)**, offline, numpy, same framing as the engine (window and hop from the config), on the dev pool. Written with a plan for a C++ mirror and a parity test like `parity.py`. Output: feature tables, labelled speech / violin / noise / sung, with the group ids.
4. **Fit (`fit.py`).** Selection rule, leave-one-group-out, leave-one-corpus-out, then `N_on`, `N_off`, thresholds by the rules above. Report the selected features and numbers, the leave-one-out spread (per speaker, per instrument), and options A and the confidence threshold side by side. Acceptance: G1 to G5 and G10 on dev (leave-one-out); if B fails here, stop and report (trigger for C); no sealed set is touched.
5. **Check on the real dev clips, once per candidate.** Run, look at the three numbers (speech notes, notes lost, display), change nothing by looking. The real dev clips may be used to choose among two or three finished candidates, never to choose a feature or a threshold.
6. **Bandwidth check.** On the real dev clips, compute the score full band and after a 7.5 kHz low-pass: the median per-frame score may shift by at most 10 % of `theta_hi - theta_lo`; if more, the 16 kHz-trained model cannot stand in for the phone and the 5 kHz band limit or the features are revised on dev before going on.
7. **Implementation (`dsp/`) on approval only,** with unit tests first (speech-like synthetic frames rejected, a harmonic string accepted, vibrato and portamento accepted, hysteresis counts, the note-level median rule, RT safety), the Python mirror, parity on dev clips and on the generated mixtures, sanitizers; then G7 and G8.
8. **Pre-registration** (seeds 44001 to 44004 and the sealed real clip list with hashes; frozen binary hash; source hashes; gates exactly as above), written and copied to the Project store before the run.
9. **Sealed runs, once each:** the sealed mixtures, then the sealed real set. Reported as measured. A failed set is not reused. A failure on one gate is a failure of the design on that gate; nothing is tuned against the set.

Clip #1 stays a check, not a training set (it may be run once per finished candidate; nothing is chosen by looking at it).

## Consequences

- Extra work per hop: the features, and probably one more transform (F2); measured against the G8 caps (voice rejection mean <= 50 us; audio-thread worst hop <= 100 us, which depends on ADR 0008) before anything is built.
- The display of a violin note after a pause is delayed by the hysteresis (`N_on` hops, at most 30 ms by G5). Note summaries are not delayed (the whole run decides).
- The synthetic sealed sets say nothing about this change; they are spent and stay spent. Regression is G7 on dev seeds and the unit tests.
- The shipped model is a handful of numbers fitted on CC BY data; no audio ships.
- Children's voices overlap the violin's pitch range; the per-group G1 makes that visible instead of averaging it away.

## Decisions (Kelechi, 2026-11-22 21:58)

1. **Number budget:** up to 10 free numbers (5 logistic weights and bias, 2 thresholds, 2 hysteresis counts, 1 window). Approved.
2. **Per-group G1:** native adults, non-native adults and children each meet 0.5 notes per minute; no pooling. Approved.
3. **Singing and humming:** measured and reported, not gated. Approved.
4. **CPU:** measure first, then amend. Caps: voice rejection mean <= 50 us per hop; audio-thread **worst** hop <= 100 us on desktop (corrected 2026-11-23: worst hop, not mean). The HMM and change-point fit move to a worker thread first (ADR 0008). The Android factor is measured on a low-end phone in Phase 2.
5. **Real set size:** each real set (dev and sealed) needs at least 10 minutes of playing and at least 4 minutes of speech, including clips with speech over playing. Approved; Kelechi records to that spec.
6. **Attribution:** `docs/THIRD_PARTY_DATA.md` lists every dataset used with licence and citation. Approved; created, entries marked "not yet received" until the data arrives.
7. **G5:** <= 30 ms added delay at violin onsets only; sustained-note display latency keeps p95 < 50 ms. Approved 2026-11-23.
8. **Uploads, in this order (Kelechi):** LibriSpeech test-clean, NSynth test plus validation (with `examples.json`), speechocean762 (with the speaker age and gender metadata), then MUSAN noise (with its LICENSE files). Real clips (about 7 dev, about 8 sealed), the CI log and the NSynth results for Phase 2 are pending separately.

## Other findings from clip #1 (not part of this proposal; each needs its own evidence and amendment)

- **Octave errors, always upward**: A4 for A3 for 357 ms at the head of a note, E6 for E5 for 168 ms at its tail, and C#4 plus A4 for A3 for about 440 ms near the end. pYIN does not make these errors on the same frames. See ADR 0007.
- **Two same-pitch splits** (B4 and C5, RMS dips of 9 to 14 dB inside a long note, pitch continuous): deferred to the Phase 3 scale grader.
- **The E4/D4 merge** is fixed by ADR 0004 Amendment 4 (certified 2026-11-22).
- **A note ended early**: the held last G3 ends when YIN confidence falls below its threshold while pYIN keeps G3 for another second of decay: deferred.
- The noise gate learns its floor from the first 0.5 s of audio; this clip starts with speech, so the floor was learned from speech. Whether that mattered was not measured; the mixture generator's no-lead-in condition measures it.
