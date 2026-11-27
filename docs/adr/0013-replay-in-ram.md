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
