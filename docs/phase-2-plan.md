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

## Plan (2026-11-23, Kelechi's four items; architecture in ADR 0009)

Android first, iOS after. Tests first; an ADR for anything new; PRs only when CI is green; self-merge only under the rule in `CLAUDE.md`.

1. Oboe audio shim (Kotlin glue and JNI, linking libintono): unprocessed input preset, low-latency exclusive mode with fallback, drone output path.
2. Flutter skeleton with `dart:ffi` bindings from ffigen and ring-buffer polling on vsync.
3. Minimal live-meter screen: note, cents, needle.
4. On-device bench mode: worst hop, latency, xruns, with and without the denormal guard.

Sequence and open questions: ADR 0009. The measurements listed above (worst hop, polling power, worker latency and queue depth) are taken with the bench mode on the real phone.

## Remaining Android items (Kelechi, 2026-11-27)

1. **Bench run** on the Infinix Note 30: done, two runs (2026-11-27); numbers in ADR 0008 Amendment 2.
2. **Battery and the 30-minute soak: deferred to Phase 5 hardening** (Kelechi, 2026-11-27: the bench shows the hop far inside its budget,
   risk low; intrinsic worst 52.3 us = 1.0 %, raw and live maxima 5 to 8 %). The soak mode (#17) is the tool then; manual battery % (no adb on the hotspot phone, 1 % resolution), with the
   in-app process CPU % difference as the primary figure. W3/W4 on a phone stay unmeasured until then (ADR 0008 Amendment 2).
3. **Device-cap amendment** (ADR 0008 Amendment 2) from the two bench reports: the audio thread's worst hop on this phone.
4. **Android Phase 2 closes on the bench evidence** (Kelechi, 2026-11-27): tag `phase2-android-complete` when the amendment is merged
   (Kelechi pushes tags).

The true low-end 2 GB device is still due before Phase 5 (ADR 0009 answer 1); the mid-range numbers are not the low-end numbers.

## iOS (Kelechi, 2026-11-27; architecture in ADR 0010)

- The iOS shim is built on **AVAudioEngine** (real-time `AVAudioSinkNode` capture and `AVAudioSourceNode` drone, the same portable
  `AudioPump` as Android) and tested **on the iOS Simulator in CI only**.
- **Real-iPhone testing moves to just before the iOS launch, through TestFlight.** Until then no iOS number comes from a device; the iOS
  device caps and the ADR 0008 measurements on an iPhone are taken in that pre-launch milestone.
- Phase 2's iOS part closes on Simulator evidence (`phase2-ios-sim-complete`: build, symbol checks, XCTest smoke tests green). The shared
  C++ stays in `android/shim/src/`; Apple Developer Program enrolment waits until the TestFlight milestone (ADR 0010 answers).

## Device results (Kelechi, Infinix Note 30, Android 14)

**First device sanity result (2026-11-23, PR 3 debug APK, Bluetooth off, drone off and never toggled).** A 440 Hz tone played from another device through the air into the phone's microphone: the meter read A4 at +0.1, -0.1 and +0.0 cents. So the whole path (Oboe capture with the Unprocessed preset, `libintono`, ffigen bindings, vsync polling) works end to end, and the accuracy through speaker, air and microphone is within +-0.1 cents for a pure tone. Humming was not detected because the voice was below the 180 Hz search floor (`min_hz`), as designed.

Stats over 6233 hops (about 33 s): hop time median 147.5 us, p99 344.1 us, max 1514.4 us (the hop budget at 48 kHz is 5333 us, so the median is under 3% of it); callback max 1516.2 us; "input gaps" 353 (about 10 per second); output xruns 0. Debug build, JIT Dart, mid-range phone: these are not final numbers.

Findings and what was done about them (PR 5, first slice):

1. **Input gaps without the drone.** The count was a wall-clock test (a callback later than 1.5 periods), which in shared mode mostly counts bursts, not lost audio. A gap is now defined by the stream: a discontinuity of the AAudio frames-read counter, with the time and size of each logged. Three counts are reported side by side: late callbacks (the old test, renamed), position gaps with frames lost, and the stream's own overrun count. Which of them is real on this phone is for the next device run to say. See ADR 0009 Note 2.
2. **Stats panel not live.** It was read once at Start, when no hop had run. It now refreshes twice a second while running.
3. **Hop maximum 1514 us against a median of 147 us.** Every hop slower than 1 ms is logged with its time (CLOCK_MONOTONIC seconds), and the app logs UI frames over 20 ms in the same clock, so a slow hop can be matched to UI work. CI now also builds an arm64 profile APK (`intono-flutter-profile-apk`), which runs Dart ahead-of-time like a release build: the next run should use it to see whether the spike remains.
