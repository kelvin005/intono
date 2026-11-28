# ADR 0013: Replaying the student's own audio after a scale run, in RAM only

Status: **Accepted** (Kelechi's decision, 2026-11-27, recorded here). Needs Kelechi's "merge". Implemented with the scale review screen
(ADR 0011 item 4).

## Context

The architecture doc's "Play, then review" (Practising without staring) offers tap-to-replay of the student's own audio on the results
screen. That means keeping the run's audio on the phone until the review ends. The standing rule is "never log or upload audio";
Kelechi wants replay in v1 without weakening it.

## Decision (Kelechi, 2026-11-27)

- **RAM only.** The last **60 seconds** of the current scale run are kept in a preallocated ring in memory (mono float at the stream rate,
  about 11.5 MB at 48 kHz; 16-bit would halve it, an implementation choice). Older audio is overwritten as the run goes on.
- **Discarded when the review screen closes**, and also when the app goes to the background, when a new run starts, and when the session
  stops. The memory is zeroed before it is released.
- **Never written to disk, never uploaded,** never passed to any OS facility that persists it (no files, no cache, no media library, no
  share sheet, no backup). The rule "never log or upload audio" stays true and is not amended.
- Replay plays the stored slice of one graded note (from its `t_start` to `t_end`) or the whole run, through the normal output path, with
  the microphone paused while it plays so the engine does not grade the playback (as the doc asks for spoken tips).

## How it fits the audio rules

- The audio thread copies each input block into the ring: a `memcpy` into memory allocated before capture starts. No allocation and no
  lock on the audio thread (`test_rt_safety` covers it). The UI thread reads the ring only after the run has stopped.
- Free play (the live meter) keeps nothing: the ring exists only during a scale run.

## Tests (with the implementation)

- The ring keeps exactly the last 60 s and wraps correctly; a note's slice maps to the right samples.
- Closing the review screen, backgrounding the app and starting a new run each release and zero the buffer.
- No file is created during a run and review (the app's documents, cache and temp directories are unchanged).
- RT-safety with the ring armed.

## Consequences

- Up to about 11.5 MB of RAM during a scale run and its review; nothing outside the app process.
- The privacy label and data-safety form stay "no data collected" (ADR 0012): audio is processed in memory, never stored or sent.

## Implementation note (2026-11-28)

- **Where the ring lives.** `ReplayRing` is in the portable shim (`android/shim/src/replay_ring.*`), which Android and iOS share. It is
  owned by `AudioPump`.
- **The time base.** Every input frame is counted from the session's first frame, which is the engine's own sample clock, so a note's
  `t_start`–`t_end` maps exactly to its samples.
- **Playback rate.** The output path runs at the input rate on both platforms (Oboe asks for the input rate; iOS's source node uses
  the input format), so playback is pitch-exact with no resampling.
- **The audio-thread handoff.** Each audio thread sets a busy flag before it loads the buffer pointer, and `release()` clears the
  pointer and waits for both flags (seq_cst on both sides). The buffer is then zeroed through a volatile pointer, so the stores cannot
  be optimised away, and freed. `arm()` on an armed ring releases first, and the destructor releases.
- **In review (frozen)** the microphone reaches neither the engine nor the ring, so nothing grades the playback. Stream statistics
  start afresh after the pause, so it is not counted as an input gap.
  - **Android** also stops the input stream at freeze, so the system microphone indicator goes off during review.
  - **iOS** (Kelechi 2026-11-28: the indicator must be off during review, before TestFlight; #46). At freeze the session's
    `AVAudioEngine` (input and output) stops, and playback goes through a second engine with an output node only, under the playback
    category. That engine never touches the input node, so no input IO runs and the indicator turns off. Release stops it, before the
    pump is freed. XCTest checks on the Simulator: input running before freeze, not after; the playback category; the review engine
    running until release.
- **Lifecycle (app).** The ring is armed after capture starts and frozen when the run ends. It is released, then the session stopped,
  when any of these happens:
  - the user leaves the review;
  - a new run starts ("Play again");
  - the app goes to the background, during a run (graded, nothing kept) or during review;
  - the screen closes.
- **Tests.**
  - The shim: 15 ring and pump tests, covering:
    - keeping the last 60 s and wrapping;
    - the frame clock;
    - slices with fades;
    - clamping;
    - zero-before-free, checked by an allocator spy;
    - re-arm;
    - the destructor;
    - release racing both audio threads;
    - the pump pausing input;
    - playback replacing the drone;
    - **no file opened** during a whole run, review and release (Linux `/proc/self/fd`).
  - RT-safety with the ring recording and playing.
  - TSan and ASan clean.
  - Dart: 12 review-screen lifecycle tests.
  - The "no file" check runs on the shared C++ on the host. The platform glue (Kotlin, Swift) only passes calls and never sees a
    sample.
