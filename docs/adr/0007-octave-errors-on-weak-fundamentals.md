# ADR 0007: Octave errors on weak fundamentals (real clip #1)

Status: Proposed (diagnosis and offline measurements only; nothing implemented; the DSP freeze stands)
Date: 2026-11-22
Owner: Kelechi

## Context

Real-audio clip #1 (third-party, internal testing only) shows four octave-up episodes
(YIN reports twice the true frequency; pYIN agrees with the true pitch):

| Episode | Where | Length |
|---|---|---|
| 1 | A3 head, 5.3-5.8 s | about 357 ms, 63 frames |
| 2 | E5 tail, 24.6-24.8 s | 31 frames |
| 3/4 | A3 descending, 31.7-32.05 s | 40 frames |

Frame counts are the voiced frames labelled "err" (YIN within 80 cents of one octave above pYIN).

## Mechanism

1. On a weak fundamental the signal repeats nearly as well after half the true period as after the full period (the 2nd harmonic dominates). YIN takes the first dip under 0.12, and on these frames that is the dip at tau = T/2, so it reports twice the true frequency. The true period sits at 2 x tau_reported, and d'(2 x tau_reported) is usually much smaller than d'(tau_reported): median ratio 0.06 in error frames vs 1.89 in healthy frames.
2. The existing OctaveGuard cannot catch these. It acts only on jumps of about one octave relative to the last stable pitch, and only for frames with confidence above 0.9 until 3 frames agree. Error frames have confidence of about 0.88 or higher by construction (a dip under 0.12), so they count as a confident new octave and are accepted after 3 frames. It also forgets its reference on any unvoiced frame, and each episode starts at or right after a note change or a dropout, where the guard has no stable pitch to compare with.

## Offline measurements (real clip #1, 44.1 kHz; dev synthetic clips; no engine change)

Healthy frames = voiced frames within 80 cents of pYIN. Error frames as above.

Spectral subharmonic ratio (magnitude at f/2 over magnitude at f, 8192-point FFT):

| | median | p5 | p95 | max |
|---|---|---|---|---|
| healthy (3194 frames) | 0.015 | 0.004 | 0.061 | 0.553 |
| error (141 frames) | 0.040 | 0.014 | 0.072 | 0.170 |

The distributions overlap almost completely. **A spectral subharmonic check does not separate the cases on this clip and is not proposed.**

Rule R(kappa, dmin): move to the lag 2 x tau (the octave below the reported pitch) when d'(2 x tau) < kappa x d'(tau) and d'(tau) >= dmin. Only frames where 2 x tau fits in the YIN lag range can be tested (1568 of 3194 healthy frames; d'(2 x tau) is undefined beyond tau_max + 1). Counts are frames that the rule would flip.

| kappa, dmin | healthy flips (of 1568) | ep 1 | ep 2 | ep 3/4 |
|---|---|---|---|---|
| 1.0, 0 (the "comparably deep" rule) | 317 (20.2%) | 63/63 | 15/31 | 34/40 |
| 0.5, 0.02 | 0 | 63/63 | 6/31 | 18/40 |
| 0.1, 0 | 0 | 59/63 | 4/31 | 18/40 |

**The "prefer 2 x tau when its dip is comparably deep" rule is unsafe as stated**: it would move one in five healthy frames to the wrong octave. A rule that is safe on this clip (kappa of about 0.1 to 0.5 with a floor on d'(tau)) fixes episode 1 almost entirely but only a fraction of episodes 2 and 3/4, and it is blind where 2 x tau is outside the lag range (low notes). Ratios and floors above were chosen by looking at this one clip, so they are a measurement, not a tuned parameter.

Onset-aware guard (relax the guard within 6 frames of an RMS onset, force-accept after 40 held frames):
- Real clip: 151 octave-wrong frames vs 128 with the current guard, i.e. **worse**. Episode 1 begins at an onset, so the guard accepts the wrong octave.
- Dev synthetic clips (seeds 9101, 9102): 207 of 135,319 voiced frames change. Not proposed.

## Proposal

No code change now. Candidate fix to evaluate **after** the real dev clips exist (never on the sealed real set): a CMNDF-based octave-down correction (moving to 2 x tau) with a kappa near the safe range above, extended to lags beyond tau_max for the test only. It needs a longer analysis window for low notes, so it touches the latency budget and goes through an amendment to ADR 0004 or a new ADR.

Decision requested: keep the freeze. Choose kappa (or any other parameter) only on the real dev set (about 7 clips); the sealed real set (about 8 clips) is run once, after the design and parameters are fixed, and never used to choose anything. (This corrects my earlier draft, which proposed rerunning on the sealed set before choosing kappa.)

Direction from Kelechi (2026-11-22, to be written up as the full proposal): replace the single-frame octave choice with multi-candidate tracking. Keep the tau, 2 x tau and tau/2 candidates per frame (candidate lag search extended to about 90 Hz for checking only, never reported), and choose with a Viterbi path that penalises octave jumps. Note summaries share the note-HMM lag; the live display keeps a short-lag decision. Offline comparison against the kappa rule, and against CREPE-tiny as a fallback. Not started; waits for the real dev set.

## Limits of this evidence

One clip, one violin, one phone. pYIN is a reference, not ground truth. Only 3 episodes (4 counted by the user).

## Follow-up owed to ADR 0004 (Kelechi, 2026-11-22)

ADR 0004 Amendment 4 treats a dwell of the note-HMM path shorter than 12 frames as an octave-error glitch, not a note. When this ADR's multi-candidate tracking is implemented, revisit that rule: if the octave errors no longer reach the HMM, remove it or justify it again with evidence; either way re-run the test `ARealNoteOf80To90MsInsideAFastRunSurvivesTheGlitchRule` and the short-run dev seeds (9301 to 9312).
