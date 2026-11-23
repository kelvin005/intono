# Real-audio clip #1: frozen engine (dsp-v0.1-synthetic), measured

Third-party phone-style tutorial video (AAC, 44.1 kHz, 33 s). Internal testing only: the clip lives in the gitignored `testdata/real/` and is never committed or shipped. This report holds measurements only, not the audio. No tuning to this clip; no DSP change was made.

Setup: audio extracted to mono 44.1 kHz PCM (no resampling), `intono-cli --notes 1` from the frozen binary (sha256 8fa82ac4a3000dd2..., source unchanged since the sealed-set-3 gate), A4 = 440 Hz, default tuning. Reference: my own pYIN pass (librosa 1.0.1, 2048 window, hop 256, 2 cent pitch grid; the default 10 cent grid made 4 to 6 cent differences look real). pYIN is not ground truth: it is a YIN derivative and shares some failure modes with the engine, so agreement is weak evidence. Expected content, as given: speech 0 to 3.8 s, 10 to 12 s, 16 to 18 s, 22 to 24 s, 27.1 to 28.9 s; G major scale ascending 3.8 to 27.1 s (15 notes), descending in semiquavers 28.9 to 33.4 s (15 notes, about 190 ms each, last G3 held). Speech region edges are approximate.

## Summary

- 47 notes emitted: 13 in speech regions, 34 elsewhere.
- Of 30 expected scale notes: 27 have a note of the right pitch. Missing or wrong: the descending A3 (reported as a garbage C#4 plus an A4 octave error); the descending E4 and D4 are merged into one note (pitch D#4, sd 87 c), so one of the two is missed.
- Extra notes outside speech: 6. Four octave errors (all one octave too high: A4 for A3 at 5.39 s, E6 for E5 at 24.63 s, C#4 garbage and A4 for the descending A3 at 31.74 to 32.18 s), plus two same-pitch splits (B4 and C5 each in two pieces).
- Speech: 13 notes in about 11.6 s of speech (5, 2, 2, 3, 1 per region), from 369 voiced frames (18 % of the speech frames; about 2.0 s). pYIN's own voiced flag is on for 75 % of the same frames, so it has no voice rejection either.
- Cents: on the 29 correctly pitched notes the engine mean and the pYIN mean (same frames, 30 ms guard) differ by a median of 0.4 c, p90 2.5 c, max 4.6 c (G4 at 30.47 s: engine -194.6, pYIN -199.2, median -194.4). No correctly pitched note differs by more than 5 c.
- Where they disagree by more than 5 c: the octave errors and the merged note (pYIN is right: its contour shows A3, E5, and two separate plateaus at E4 and D4, which also match the expected sequence), and the speech notes (neither is right: speech has no stable pitch; pYIN and the engine differ by 5 to 37 c on those because the pitch is moving).
- Players' intonation reported as measured: descending C5 -20.9 c and D5 -12.2 c, F#4 +12.6 c (ascending); pYIN agrees within 1 to 2 c, so those are the player's, not the detector's.

## Observations that are not in the list above

- The B4 and C5 each contain RMS dips of 9 to 14 dB about every 190 ms while the pitch stays continuous (pYIN plateau at +192 to +206 c, then +300 to +308 c). The engine split B4 at the deepest dip (30 dB below peak) and C5 once; it did not split at the shallower ones. Whether those are real re-articulations or one long bow cannot be told from the audio; the on-screen notation says one note each.
- The final G3: the engine ends it at 32.415 s when YIN confidence falls below its threshold (0.88 at the last voiced frame, falling) while the level decays from -18 to -45 dB; pYIN keeps G3 (with +-15 c wander) for another second.
- Octave errors happened with real notes up to 357 ms long (A4 for A3), not only 1 to 4 glitch frames as in the synthetic data.

## Note list

| # | start s | dur ms | note | mean c | sd c | conf | frames | assessment |
|---|---|---|---|---|---|---|---|---|
| 0 | 0.592 | 267 | C4 | -33.5 | 107.1 | 0.91 | 20 | speech |
| 1 | 1.097 | 52 | C4 | -43.1 | 0.0 | 0.94 | 10 | speech |
| 2 | 2.101 | 215 | A#3 | +8.1 | 55.4 | 0.94 | 14 | speech |
| 3 | 2.815 | 213 | C4 | +40.8 | 70.3 | 0.96 | 28 | speech |
| 4 | 3.029 | 147 | A3 | +0.3 | 11.8 | 0.93 | 24 | speech |
| 5 | 3.924 | 1463 | G3 | -3.0 | 1.3 | 1.00 | 242 | ok |
| 6 | 5.390 | 357 | A4 | -1.5 | 2.7 | 0.94 | 62 | octave error: true A3 (pYIN -1203 c), head of the A3 note |
| 7 | 5.750 | 856 | A3 | +1.6 | 1.6 | 1.00 | 148 | ok |
| 8 | 6.612 | 1509 | B3 | +6.7 | 2.2 | 0.99 | 243 | ok |
| 9 | 8.127 | 1631 | C4 | +2.5 | 4.1 | 1.00 | 282 | ok |
| 10 | 10.281 | 81 | C#4 | +36.5 | 94.9 | 0.92 | 12 | speech |
| 11 | 11.169 | 75 | E4 | -28.0 | 2.2 | 0.95 | 10 | speech |
| 12 | 12.103 | 842 | D4 | -1.1 | 1.7 | 1.00 | 146 | ok |
| 13 | 12.980 | 1004 | E4 | +2.3 | 3.2 | 0.99 | 157 | ok |
| 14 | 13.990 | 935 | F#4 | +12.6 | 1.7 | 0.99 | 162 | ok |
| 15 | 14.928 | 1402 | G4 | +1.6 | 4.9 | 0.99 | 238 | ok |
| 16 | 16.863 | 151 | A#3 | +0.6 | 63.8 | 0.95 | 23 | speech |
| 17 | 17.595 | 342 | D4 | -24.9 | 393.3 | 0.93 | 39 | speech |
| 18 | 18.721 | 813 | A4 | +5.2 | 2.2 | 1.00 | 141 | ok |
| 19 | 19.545 | 360 | B4 | -4.3 | 4.3 | 0.98 | 59 | one expected B4, split in two (RMS dips of 9-14 dB inside it) |
| 20 | 19.946 | 377 | B4 | +3.4 | 2.1 | 0.99 | 64 | second piece of the B4 |
| 21 | 20.323 | 389 | C5 | +3.4 | 2.8 | 0.99 | 66 | one expected C5, split in two (RMS dips inside it) |
| 22 | 20.718 | 372 | C5 | -0.5 | 2.4 | 0.99 | 65 | second piece of the C5 |
| 23 | 21.095 | 964 | D5 | +4.5 | 5.2 | 0.99 | 160 | ok |
| 24 | 22.460 | 151 | A#3 | +39.9 | 110.9 | 0.94 | 25 | speech |
| 25 | 23.545 | 87 | F4 | +40.0 | 5.0 | 0.96 | 16 | speech |
| 26 | 23.679 | 128 | G#4 | -48.9 | 470.4 | 0.94 | 23 | speech |
| 27 | 24.247 | 377 | E5 | +6.7 | 1.3 | 0.99 | 66 | ok |
| 28 | 24.631 | 168 | E6 | +7.9 | 0.5 | 0.99 | 30 | octave error: true E5 (pYIN +707 c), tail of the E5 note |
| 29 | 25.141 | 406 | F#5 | -1.2 | 1.3 | 0.99 | 71 | ok |
| 30 | 25.960 | 1051 | G5 | -1.4 | 3.8 | 0.99 | 172 | ok |
| 31 | 27.051 | 116 | A#3 | -10.2 | 14.9 | 0.94 | 18 | speech |
| 32 | 28.996 | 215 | G5 | -2.0 | 1.7 | 0.99 | 34 | ok |
| 33 | 29.217 | 203 | F#5 | -1.9 | 2.3 | 0.99 | 31 | ok |
| 34 | 29.425 | 209 | E5 | +3.7 | 1.4 | 0.98 | 29 | ok |
| 35 | 29.637 | 183 | D5 | -12.2 | 3.4 | 0.98 | 30 | ok |
| 36 | 29.826 | 209 | C5 | -20.9 | 1.4 | 0.99 | 33 | ok |
| 37 | 30.041 | 186 | B4 | -3.6 | 1.8 | 0.99 | 31 | ok |
| 38 | 30.232 | 232 | A4 | +4.2 | 1.7 | 0.99 | 36 | ok |
| 39 | 30.470 | 192 | G4 | +5.4 | 2.0 | 0.99 | 32 | ok |
| 40 | 30.668 | 238 | F#4 | +7.0 | 1.4 | 0.99 | 30 | ok |
| 41 | 30.912 | 337 | D#4 | +44.7 | 87.3 | 0.96 | 48 | MERGED: expected E4 then D4 (pYIN plateaus at -500 and -702 c, 18 dB level dip between) |
| 42 | 31.289 | 192 | C4 | -1.2 | 2.4 | 0.99 | 34 | ok |
| 43 | 31.573 | 75 | B3 | +0.2 | 3.6 | 0.94 | 14 | ok, short (75 ms) |
| 44 | 31.742 | 163 | C#4 | +43.0 | 580.3 | 0.94 | 29 | WRONG: expected A3 (pYIN -1207 c); octave-glitched frames, sd 580 |
| 45 | 31.910 | 267 | A4 | -0.0 | 10.4 | 0.98 | 29 | WRONG: octave error, true A3 (pYIN -1205 c) |
| 46 | 32.180 | 235 | G3 | -3.0 | 0.4 | 0.97 | 41 | G3 ok but truncated: ends 32.4 s, pYIN stays on G3 to the end of the clip (33.4 s) as it decays |
