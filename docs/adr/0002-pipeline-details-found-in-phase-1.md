# ADR 0002: Pipeline details settled while building libintono

Status: Accepted (Kelechi, 2026-11-21). The note summaries listed under "Not done" are settled by ADR 0003.

## Context

Building the C++ core against the Phase 0 reference exposed four behaviours the architecture doc does not specify. Each was found by a failing test or an odd frame in the CLI output, not guessed in advance.

## Decisions

1. **YIN range-edge guard.** A minimum that sits on the first or last lag of the search range is not a period. At a note attack the partial window reported 3200 Hz (`max_hz`) as a voiced frame. YIN now reports "not found" for those. Supported range tops out at E7 (2637 Hz), so no real note is affected.
2. **YIN silence guard.** All-zero input made every lag match perfectly, so YIN claimed a pitch. It now reports "not found" when the window energy is below 1e-12. The noise gate already hid this in the pipeline; the guard makes `Yin` correct on its own.
3. **Onset flag (`is_onset`).** Two triggers, at most one onset per 10 frames (about 53 ms):
   - RMS rise over 6 dB against the quietest of the previous 3 frames, while the gate is open.
   - A pitch step: the note-change reset of ADR 0001 fires, the new raw pitch is more than 50 cents from the old note's displayed centre, and it stays there for 6 frames (about 30 ms).
   - Voicing that resumes within 20 frames (about 107 ms) of a dropout and lands more than 50 cents from where it left off also counts, because a legato note change often loses one frame.
   Amended by ADR 0003: a second pitch trigger for legato steps smeared over several frames, and consecutive jump frames no longer restart the confirmation.
   The first version of the pitch trigger compared the displayed centre with an anchor. Before vibrato is established the displayed centre wobbles by up to the vibrato extent, so 4 of 136 synthetic clips fired a false second onset. The step-based trigger removed all of them (onset F1 0.986 to 1.000).
4. **Frame semantics the C API comments leave open.** `intono_frame.hz` is the displayed vibrato-centre pitch; `t_sec` is the window centre; `midi_note` is the ET note nearest the target; drone timbre 0 is a sine and 1 has 8 harmonics. These are documented in `intono.h` as comments only; no struct or function changed.

## Not done, needs a decision (the C API is a contract)

- Note summaries: the C API had no call for them. Decided in ADR 0003: add `intono_read_notes` on a second SPSC ring.
- Drone notch filters for speaker leakage are Phase 3 and not started.

## Consequences

- The Python reference carries the same guards and the same note-change rule, so `run_cpp.py` still compares frame by frame (max difference 0.001 cents on the synthetic set).
- Thresholds (6 dB, 50 cents, 30 ms, 53 ms, 107 ms) are constants at the top of `dsp/src/engine.cpp`; move them to remote config if field data asks for it.
