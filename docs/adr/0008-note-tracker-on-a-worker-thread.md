# ADR 0008: Move the note HMM and change-point fit off the audio thread

Status: **Accepted and implemented** (2026-11-23). Approved by Kelechi 2026-11-23 12:40 with the prerequisites and gates recorded in Amendment 1, which also holds the profile of the 210 us hop (it was denormal arithmetic, not the flush), the denormal fix, and the measured results. DSP is frozen on synthetic data (ADR 0004); this changes where code runs, not what it computes, and is gated on identical output (M3, passed). Open: W2 (waits for ADR 0006), M5 and the polling battery cost (Phase 2, on a low-end phone). Date: 2026-11-23. Owner: Kelechi.

## Context

Real-time safety is about the worst hop, not the mean (Kelechi, 2026-11-23). The audio callback has a hard deadline; one slow hop is a glitch whatever the average is. ADR 0004 argued from the mean (2.0 us per hop for the tracker, "36x margin" for its worst hop against the 5333 us hop). That argument was wrong in kind: the audio thread's budget is the callback's buffer period, shared with the drone renderer and the app, and a worst hop is what a deadline sees.

### Measured today, BEFORE the fixes (superseded by Amendment 1: the 210 us maxima were denormal arithmetic) (whole engine, the CI-style Linux Release build, one hop of 256 samples per `intono_process` call)

Host: shared 2-core x86-64 VM, so wall-clock maxima include scheduler jitter (single hops of 1.5 to 5.4 ms with no relation to the code, also on a steady tone). The number that means something is the **intrinsic** cost of each hop: the **minimum over 11 repeated runs of the same hop**, pinned to one core. Tool: `worst_hop.cpp` (to be committed as `tools/bench/worst_hop.cpp`).

| Input (30 s) | mean | p99 | p99.9 | max (intrinsic) |
|---|---|---|---|---|
| steady tone with vibrato | 13.4 us | 13.3 us | 169.5 us | **210.5 us** |
| fast legato scale (47 hops per note) | 14.7 us | 69.7 us | 170.8 us | **210.7 us** |
| real clip #1 (44.1 kHz, internal) | 13.5 us | 13.8 us | 170.1 us | **210.7 us** |

- The mean is 13 to 15 us. The fits show in the p99 of the scale (70 us against 13 us on a steady tone: about one hop in forty-seven).
- The maximum is **about 210 us on all three inputs, including the steady tone**, so it is not the change-point fit. On the steady tone the hops above 100 us are the 8 consecutive hops at the end of the stream, where the run ends in silence; it coincides with the tracker's phrase-end flush (decode of the pending frames and the closing statistics). I have not profiled it further; the profile is part of the work on this ADR.
- Against the cap of 100 us on the audio thread's worst hop (below), the engine **already fails by a factor of two on this host**, before voice rejection (ADR 0006) adds its own cost. The earlier 147 us (tracker alone, fit hop) is consistent with this.

## Decision

Split the engine into two threads. Output of the notes does not change.

**Audio thread (`intono_process`, real-time): keeps**
DC filter and band limiting, window, RMS and noise gate, YIN, octave guard, vibrato centre and display pitch (ADR 0001), the onset flag, **voice rejection and `is_voiced` (ADR 0006)**, the frame ring, and one push of a hop record to the queue. Nothing else.

**Worker thread (owned by the engine): takes**
`NoteTracker` as it is: the fixed-lag note HMM, the change-point fit, the segmenter, the robust statistics (ADR 0004), `emit_note`, and the note ring (producer: the worker; consumer: the UI thread through `intono_read_notes`, still a single consumer).

**Queue.** `SpscRing<HopRecord>` (the existing lock-free ring: release/acquire, preallocated, wait-free for both sides). The record holds what `NoteTracker::update` is given today: `note_voiced`, `rms_onset`, `NoteFrame` (`t`, `conf`, `c`, `vr`, `vw`, `ctr`), the raw cents re `a4`, a frame index, and, after ADR 0006, the instrument score. About 64 bytes. Capacity 1024 records (5.4 s, the same as the frame ring), 64 KiB.

**No wake-up call from the audio thread.** A condition variable or semaphore notification is a system call on the audio thread; it is not used. The worker polls: when the queue is empty it sleeps 2 ms (`nanosleep`), so a record waits at most about 2 ms plus the processing. About 500 wake-ups per second while running; the power cost is measured on the phone in Phase 2, with an adaptive back-off (longer sleeps while the gate is closed) as the fallback.

**Overflow.** If the queue is full the audio thread drops the record (never blocks, as the frame ring does) and counts it. The worker sees the gap in the frame index and ends the run at it (flush), so no frame is invented across the hole. The counter is an internal statistic.

**Lifecycle.** `intono_create` starts the worker (allocation and thread creation are allowed there: not real-time); `intono_destroy` sets a stop flag and joins it. If the thread cannot be created, `intono_create` returns NULL. The thread is named `intono-notes` and runs at normal priority; raising or lowering it (Android priority, iOS QoS) is the platform glue's job, not the library's. Records still queued at destroy are discarded; the existing "feed ~120 ms of silence to read the last note" contract still works, because the worker processes those silent hops like any other.

**Inline mode for tests and tools (not public).** An internal header (`engine_internal.hpp`, not exported) provides `engine_set_inline(e, true)` before the first `intono_process` and `engine_drain(e)`. In inline mode no thread is started and `intono_process` calls the tracker directly, exactly as today. The CLI, the Python parity checks, the sealed-set runners and the unit tests use inline mode, so every number already certified stays reproducible. The threaded path is tested separately (M3, M4).

### The C API

**Unchanged: no function, struct or field changes.** Two comment-only additions to the semantics block, recorded here as the change: (1) notes are produced by a worker thread the engine owns, and may be read some milliseconds later than the audio-time they are stamped with; (2) `intono_create` also returns NULL if that thread cannot be created. `intono_read_notes` stays UI-thread only, `intono_process` stays audio-thread only. If an exposed overflow counter turns out to be needed it is an API addition and gets its own ADR.

## Caps and gates (Kelechi, 2026-11-23)

| # | Gate | Limit | How |
|---|---|---|---|
| W1 | **Audio-thread worst hop**, desktop, whole of `intono_process` per hop | **<= 100 us** (intrinsic: the minimum over >= 10 runs of the same hop, pinned core), on every input below, including with voice rejection (ADR 0006) once it exists | `tools/bench/worst_hop` on: steady tone, fast legato scale, clip #1, the 10 dB noisy dev clips, phrase ends and starts, a long mixture with speech (when the data is in) |
| W2 | **Voice rejection, mean** | **<= 50 us per hop** (ADR 0006 G8) | same tool, with and without the feature enabled, difference of means |
| W3 | **Worker keeps up**, no queue growth over a **30-minute stream** at real-time pace | queue depth high-water mark <= 64 records (about 340 ms) and no upward trend (least-squares slope <= 1 record per minute) | nightly soak: 30 minutes of concatenated dev clips and mixtures fed at real-time rate; plus an accelerated run (20x) with the worker slowed by an injected delay of 8 times its measured mean cost per record, to emulate a low-end phone. Worker worst-hop is reported, not capped |
| W4 | **Note delay in wall time** | worker latency (record pushed to note in the ring) p99 <= 10 ms on desktop under load; with it, the ADR 0004 summary delay (330 ms measured in stream time) stays <= 350 ms. **That margin is thin: 330 + 10 = 340.** | soak test and the delay measurement of `run_boundaries.py` repeated in threaded mode |
| M3 | **Identical output** | threaded notes == inline notes, bit for bit, on the 420 dev clips (9101 to 9108 family), the 300 short-run phrases and the 1920 edge streams, with random worker stalls of 0 to 3 ms injected | parity tool, threaded mode |
| M4 | **RT-safety and races** | `test_rt_safety` extended to run with the worker alive: no `malloc` and no mutex lock on the audio thread (armed per thread id; the worker is not armed, but is written without locks); TSan and ASan/UBSan clean with the worker running | CI binaries |
| M5 | **Real device** | The Android factor is **measured on a low-end phone in Phase 2**, with the same tool built with the NDK; until then it is unknown. My earlier estimate of 3 to 8 times a desktop core is a guess and is not used as evidence. Device caps are then set by amendment from the measurement | Phase 2 |

## Consequences

- The audio thread's work shrinks to YIN and the display path plus voice rejection. Measured in Amendment 1: worst hop 21 to 24 us against the 100 us cap.
- A note arrives about 2 ms plus processing later than today in wall time, more if the worker is starved on a loaded phone; the display is unaffected (live path stays on the audio thread).
- One more thread to test. Behaviour of the worker under thermal throttling or app backgrounding is not measured here; the overflow policy keeps the audio thread safe and costs at most a flushed run.
- ADR 0004 needs no re-certification if M3 holds (same computation, same inputs, same order). If M3 fails, the cause is found before anything else.
- ADR 0006: the instrument score is computed on the audio thread, travels in the record, and the note-level median-score decision runs on the worker, so it adds nothing to the audio thread. ADR 0007: the multi-candidate Viterbi shares the note HMM's lag and lives on the worker; the live display keeps its short-lag decision on the audio thread, as intended.
- ADR 0005 (emulator in CI) runs the threaded path.

## Alternatives considered

1. **Keep everything inline and make the HMM, fit and flush incremental** (spread over hops so that no hop exceeds the cap). Keeps one thread and exact timing, but needs a bounded-work rewrite of the fit and the flush, changes the code that is certified, and still leaves the audio thread running it. Rejected for risk; it remains the fallback if a worker thread proves unworkable on a platform.
2. **A thread owned by the platform glue** (Kotlin or Swift calling a `intono_step_notes` function). Needs an API addition and makes every platform re-implement the loop. Rejected: the library owning the thread keeps the C API unchanged.
3. **Condition variable or semaphore wake-up from the audio thread.** A system call on the audio thread. Rejected; polling at 2 ms costs power instead, to be measured.
4. **Dropping the fit's worst cases** (fewer vibrato rates, smaller windows). Changes the certified algorithm and does not touch the flush. Rejected.

## Not known yet

- ~~What the 210 us hops at the phrase end really are~~ Answered in Amendment 1: denormal arithmetic in the filters and YIN, not the flush.
- The worst hop on a phone, and the power cost of a 2 ms polling thread.
- Whether the audio thread alone, after the split, stays under 100 us with voice rejection added (W1 decides, after ADR 0006's measurements).

## Amendment 1 (2026-11-23): profile of the 210 us hop, denormal fix, implementation and results

Kelechi approved this ADR on 2026-11-23 12:40 with a prerequisite: profile the 210 us worst hop first; if it is the end-of-run flush, move the flush computation to the worker (the audio thread only pushes a run-ended marker); W1 (<= 100 us worst hop) must then pass. `intono_destroy` must signal, join and free the worker cleanly, with a test that runs create/destroy 1000 times without leaks under ASan. W4 stays at 350 ms (amend to 400 ms by ADR only if the threaded build measurably fails it). Polling battery cost is measured in Phase 2.

### The profile: the 210 us hop was NOT the flush

Per-section timing of the audio thread (a profiling copy of the engine, intrinsic = per-hop minimum over 11 pinned runs) put the whole 210 us in **YIN, with the tracker at 0 us**, in the eight hops where the signal has just fallen into silence. Setting flush-to-zero in the benchmark process removed it (max 218 us to 17 us on the steady tone), so the cause is **denormal floating-point numbers**: after a note stops, the filter outputs decay exponentially; a float in the denormal range (below 1.2e-38) makes x86 and ARM arithmetic 10 to 100 times slower. I had missed a second effect because the benchmark appended only 0.25 s of silence: after about one second of true digital silence the **double-precision filter states** (DC blocker, two biquads) reach the denormal range too, and 600 hops of 133 us follow (6 s of silence measured). A real microphone never delivers exact zeros, but a file, a muted input and some Android audio paths do.

A third cause remained after the filter flush: the YIN FFT on a decaying tail of amplitude about 1e-17 (spectrum products below FLT_MIN: one hop of 106 us instead of 8), fixed by moving YIN's existing silence check ahead of the transform. The earlier statement in this ADR that the 210 us hops "coincide with the flush" was a coincidence of timing: they were YIN and filter arithmetic. **The tracker's own worst hop, measured inline after those fixes (same tool, `INLINE=1`), is 17.5 us (steady tone), 73.3 us (fast scale: the change-point fit) and 100.5 us (real clip #1)**, so with the tracker on the audio thread the cap would still be missed on the real clip, and the earlier 147 us figure of ADR 0004 (fit hop, other input) shows it can be exceeded. That is what the worker thread removes.

### Changes made (DSP freeze: a CI/worst-hop failure, recorded here)

1. **Denormal guard** (`filters.hpp`, `engine.cpp`): a software flush of the double filter states below 1e-30 and of the float window samples below 1e-18 (squares stay above FLT_MIN). Portable and deterministic on every platform (no MXCSR or FPCR, no change to the caller's floating-point environment). It is exact for every value above the threshold, so it can only change signals below -360 dBFS.
2. **YIN silence check before the FFT** (`yin.hpp`): the existing "digital silence" return (`e0 < 1e-12`) now happens before the transform instead of after it. The returned result is the same (no pitch, confidence 0); only the work is skipped.
3. **Worker thread, as decided above** (`engine.cpp`): `HopRecord` (80 bytes) pushed once per hop into an `SpscRing` of 1024; the worker (`intono-notes`) pops, runs `NoteTracker::update` exactly as before, and emits into the note ring. Polling sleep 2 ms; the audio thread never signals. Full queue: the record is dropped and counted, the worker sees the gap in the frame index and ends the run there (`NoteTracker::flush`, new, same closing as the end-of-run flush). `intono_create` starts the thread (NULL if it cannot be created); `intono_destroy` sets the stop flag, joins and frees. The run-ended marker the prerequisite asks for is not needed as a separate message: the audio thread already pushes a record every hop, voiced or not, and the worker's `update` closes the run when it has seen more than 20 unvoiced records (ADR 0004); a drop-induced hole is closed through the frame index.
4. **Inline mode** (`src/engine_internal.hpp`, not exported): `intono_internal::create(cfg, inline_mode)`, `drain`, queue depth and high-water, worker stall and spin hooks, a latency probe. The CLI (`--threaded 1 [--stall US]`), the unit tests (`INTONO_TEST_THREADED=1`), the parity tools and the sealed-set runners use it. **Default for the CLI and the existing tests is inline**, so every certified number is reproduced by the same path as before.
5. **C API:** no function, struct or field changed. Comment-only additions in `intono.h` (thread rules block; `intono_create`). Threads library linked (`Threads::Threads`).

### Results (Linux x86-64 Release, shared 2-core VM; the audio thread pinned, the worker free)

| Gate | Result | |
|---|---|---|
| W1 audio-thread worst hop, intrinsic (min over 11 runs), 6 s of silence appended | steady tone 20.8 us; fast legato scale 22.9 us; real clip #1 23.5 us; mean 12 to 13 us; **no hop over 100 us** (before: 218, 211, 211 us, and 600 hops of 133 us after 6 s of silence) | PASS |
| W2 voice rejection mean <= 50 us | not measured: the feature does not exist yet | open (ADR 0006) |
| W3 queue, 30 stream-minutes, worker keeps up | **real time, 30 minutes** (1800 s wall, 337,500 records, 2802 notes, 24 dev phrases + scale looped): queue high-water **11** records (cap 64), slope **-0.004 records/min** (cap 1), 0 dropped. Accelerated 20x, 30 stream-minutes in 90 s: slope 0.000, 0 dropped; high-water 106, which is the 2 ms poll sleep itself at 20x (2 ms = about 150 hop intervals at that pace) and is why the 64-record cap is judged at real-time pace only. Accelerated with the worker slowed 8x (+4.6 us per record on a measured 0.57 us mean): high-water 57, slope +0.007, 0 dropped. Worker cost per record: mean 0.6 to 1.8 us (0.1 to 0.7 % of the 5.3 ms hop) | PASS |
| W4 note delay | worker latency (record pushed to tracker done), 30-minute real-time run: mean 1.08 ms, **p99 2.15 ms (cap 10 ms)**, max 30.4 ms (a scheduler stall on the shared VM: the worker's own work was 6 ms at its worst, so the rest is waiting for a core). The 330 ms delay in stream time is unchanged (the CLI waits for the worker after every chunk, so threaded notes carry the same `emit_t` as inline); with the p99 latency it is 332 ms against the **unchanged 350 ms gate**. A single note in 30 minutes arrived about 30 ms late; that is reported, not gated, and is the number to watch on a phone | PASS (p99); max reported |
| M3 identical output | frozen binary vs new inline vs new threaded: 52 comparisons (frames and notes, with and without 3 s of appended silence, phrase seeds + real clip #1): 0 differ; threaded with random worker stalls of 0 to 3 ms: 0 differ; boundary dev gate (600 steps): report identical in all three; short-run dev seeds 9301 to 9304: identical in all three; Phase 1 harness (accuracy, 18-phrase Python parity, note scoring): identical to the frozen binary except CPU timing. Unit tests: `Worker.ThreadedNotesAreIdenticalToInlineUnderRandomStalls` (5 chunk sizes, 2 stall levels, bit for bit). Full sweep on all four phrase seeds (21, 77, 123, 2024, 292 comparisons incl. real clip #1 and padded silence): frozen binary vs new inline: **0 differ**; new inline vs threaded (1024-sample chunks, both sides, to keep the run short): **0 differ**. The earlier smaller runs used 128-sample chunks, including 16 comparisons with random worker stalls up to 3 ms: 0 differ | PASS |
| M4 RT-safety and races | `test_rt_safety` now arms per thread and runs twice (inline; worker alive): 0 allocations, 0 mutex locks on the audio thread. 80 tests pass under ASan/UBSan **three times in threaded mode**, and in inline mode; TSan: no report (inline and threaded) | PASS |
| create/destroy | `Worker.CreateDestroyThousandTimes`: 1000 create/destroy cycles (every tenth with audio queued at destroy), thread count returns to the baseline, no leak or use-after-free under ASan (LeakSanitizer on) | PASS |
| M5 phone | not measured: Phase 2, on a real low-end ARM phone (docs/phase-2-plan.md) | open |

The whole test suite (80 tests, 1 disabled, from ADR 0004) runs **twice** in ctest: inline, and through the worker (`INTONO_TEST_THREADED=1`).

Not tested here: the shared Android build (NDK, `INTONO_SHARED`); thread creation failure (no way to inject it); behaviour under thermal throttling or backgrounding (Phase 2); polling power cost (Phase 2).

### What this changes about the earlier text

- The "Measured today" table above is superseded: its 210 us maxima were denormal arithmetic, not the tracker and not (only) the flush. The mean figures (13 to 15 us) stand.
- The prerequisite's "if it is the flush" branch did not apply: the flush is not what made the hop 210 us. The worker is kept because, after the real fix, the inline tracker alone peaks at 73 to 100 us on ordinary input (table above) with only a 10 % to 27 % margin to the cap, and on a phone that margin does not exist. Threaded worst hop: 22.4, 22.4 and 23.0 us on the same three inputs.
- ADR 0006 G8 text corrected accordingly.

### Decisions added by Kelechi, 2026-11-23 14:26

- **The software denormal guard stays on every platform, even if a phone's FPU flushes denormals to zero in hardware** (portability and bit-comparable results; no MXCSR or FPCR changes by the library).
- **Phase 2 measures the worst hop on a real ARM phone** (M5), together with the polling power cost; see `docs/phase-2-plan.md`.
- Phase 2 now depends only on CI being green, not on the NSynth results or the real clips.

## Note 1 (2026-11-27): a flaky test, fixed in the test only

`Threads.AudioThreadProducesWhileUiThreadConsumes` failed once on the CI emulator (`android-test`, `main` at `a7e258b`, inline run): 1799
of 1872 frames read. The test's producer is not paced: it pushes 10 s of audio in about 370 ms into the 1024-frame ring. When the
consuming thread was descheduled for long enough on the 2-vCPU emulator, the ring filled and the newest frames were dropped, which is
the designed behaviour, not a defect. A 300 ms delay before the consumer starts reproduces it deterministically (exactly 1024 read).

The test now holds its producer back while more than 512 frames are unread, as a device-paced stream would be, and keeps the 300 ms
delay as a regression check. It still checks what it is for: strictly increasing frame times and no loss while both threads run.
Ring overflow remains covered by the worker and ring tests. **No library code changes**: `dsp/src`, `intono.h`, the gates and the
thresholds are untouched, and the default build's output is unchanged (bit-identity job).
