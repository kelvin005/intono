# Phase 2 plan: decisions recorded so far

No Phase 2 plan existed in the repository or the Project store when this was written (2026-11-23); this file holds only what has been decided, and the full plan still has to be written.

## Dependency (Kelechi, 2026-11-23 14:26)

Phase 2 now depends **only on CI being green** (ADR 0005: Linux build and tests, ASan/UBSan, TSan, the Android emulator job). It no longer waits for the NSynth results, the real clips, the voice-rejection work (ADR 0006) or the ADR 0008 prerequisites (done).

- DSP accuracy work (ADR 0006 voice rejection, ADR 0007 octave errors, the Phase 3 hard gate) continues **in parallel** as the data arrives. It stays under the DSP freeze: changes only in response to real-audio results or CI failures, each recorded in an ADR, each gated by identical output on the synthetic dev sets (G7) unless an ADR says otherwise.
- The CI log is pending: Kelechi is pushing to GitHub and will send it. Phase 2 starts when that log is green; if it is not, fixing CI comes first.

## Measurements Phase 2 owes (ADR 0008)

1. **Worst hop on a real ARM phone** (Kelechi, 2026-11-23): `tools/bench/worst_hop` built with the NDK, run on a **low-end** physical Android phone, audio thread pinned where the OS allows, intrinsic = per-hop minimum over at least 10 runs, the same inputs as on the desktop (steady tone, fast scale, clip #1, noisy clips, 6 s of silence appended). Device caps for the audio thread's worst hop are then set by an ADR amendment from the measurement. No estimate of the Android factor is used as evidence (the earlier 3 to 8x was a guess).
2. **Polling power cost** of the 2 ms worker poll (ADR 0008): battery or energy measurement on the phone, with an adaptive back-off (longer sleeps while the gate is closed) as the fallback if it is significant.
3. **Worker latency and queue depth on the phone** (W3, W4 of ADR 0008): the 30-minute soak and the p99 latency against the unchanged 350 ms note-delay gate. The worst single latency seen on the shared desktop VM was 30 ms (a scheduler stall); on a phone it is the number to watch. W4 is amended to 400 ms by ADR only if the threaded build measurably fails 350 ms.
4. **Voice rejection cost** (W2, after ADR 0006 is implemented): mean <= 50 us per hop, and the audio-thread worst hop still <= 100 us on desktop.

## Decision: the software denormal guard stays (Kelechi, 2026-11-23 14:26)

The software flush in `filters.hpp` and `engine.cpp` (ADR 0008 Amendment 1) **stays on every platform, even if the phone's FPU flushes denormals to zero in hardware** (ARM FPCR.FZ, the NEON default on 32-bit ARM, or a flush-to-zero mode the audio stack sets). Reason: portability and determinism. The guard makes results independent of the platform's floating-point mode and bit-comparable between the desktop, the emulator and the phone. Do not remove it, and do not replace it by setting MXCSR or FPCR. The phone measurement (item 1) is taken with the guard on; it may additionally be taken with it compiled out, as information only.
