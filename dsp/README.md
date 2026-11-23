# libintono (dsp/)

Real-time pitch core for Intono: audio in, `(hz, confidence, note, cents, vibrato, onset)` frames out. C++20, no dependencies except the vendored pffft. One library serves Android and iOS through the C API in `include/intono/intono.h` (a contract: change it only with an ADR).

```
mic -> DC blocker -> HP 150 Hz -> LP 4 kHz -> window 1024 / hop 256
    -> RMS + adaptive noise gate -> YIN (pffft) -> octave guard
    -> centre pitch + vibrato (ADR 0001) -> cents vs target (ET / just / Pythagorean)
    -> onset flag -> lock-free SPSC frame ring -> UI thread
                 \-> note segmenter -> second SPSC ring (64 notes) -> UI thread
```

## Build and test

```
cmake -S dsp -B build -G Ninja -DFETCHCONTENT_SOURCE_DIR_GOOGLETEST=/path/to/googletest   # or let CMake fetch v1.14.0
cmake --build build
ctest --test-dir build --output-on-failure        # intono_tests (45) + intono_rt_safety (2)

cmake -S dsp -B build-asan -DINTONO_SANITIZE=address   # ASan + UBSan
cmake -S dsp -B build-tsan -DINTONO_SANITIZE=thread    # TSan
```

`intono_rt_safety` wraps `malloc`, `calloc`, `realloc`, `posix_memalign`, `aligned_alloc` and `pthread_mutex_lock` at link time and fails if `intono_process` or `intono_drone_render` calls any of them. It first proves the wrappers can see an allocation and a lock, so a pass is not vacuous. It is Linux only and is not built together with a sanitizer.

## CLI

```
intono-cli file.wav [--a4 440] [--tuning 0|1|2] [--tonic 60] [--chunk 128] [--bench N]
```

Prints one CSV row per frame, or one per note with `--notes 1` (0.2 s of silence is appended so the last note closes). `--bench N` reports microseconds per hop. WAV: PCM 16/24/32 or float32, any channel count (mixed to mono).

## Accuracy

```
python tools/accuracy/run_cpp.py --cli build/intono-cli
```

Scores the C++ output on the synthetic set with the Phase 0 metrics, checks it frame by frame against `tools/accuracy/ref/yin_ref.py`, and exits 1 if a gate target or the Phase 0 regression limit is missed.

## Layout

| File | Role |
|---|---|
| `include/intono/intono.h` | public C API |
| `src/engine.cpp` | streaming pipeline, onset logic, C API |
| `src/yin.hpp` | YIN with pffft |
| `src/post.hpp` | octave guard, centre pitch and vibrato tracker |
| `src/tuning.hpp` | cents maths and tuning tables |
| `src/filters.hpp` | DC blocker, Butterworth biquads |
| `src/drone.hpp` | additive drone synth |
| `src/ring.hpp` | lock-free SPSC ring |
| `src/notes.hpp` | note segmenter and robust note statistics (ADR 0003, 0004) |
| `src/notes_hmm.hpp` | fixed-lag note HMM and change-point fit that decide note boundaries (ADR 0004) |
| `third_party/pffft` | vendored pffft (BSD-style licence, float only) |

## Threading

- `intono_process`, `intono_drone_render`: audio thread only. No allocation, locks, logging or syscalls.
- `intono_read_frames`, `intono_read_notes`: UI thread only. A note is emitted when it ends: ~213 ms plus the note HMM's switch delay (at most ~330 ms measured; the limit is 350) after a pitch change, at the frame of an RMS onset, or ~107 ms after the last voiced frame at a phrase end; there is no flush call.
- `intono_set_tonic`, `intono_drone_set`: UI thread; they reach the audio thread through relaxed atomics.
- `intono_create` / `intono_destroy`: any thread, not real-time. Never destroy while the audio thread is inside `intono_process`.
- If the UI falls behind by more than 1024 frames (about 5.4 s) new frames are dropped, never overwritten.

## Not implemented yet

Drone notch filters and the NLMS canceller (Phases 3 and later), the optional CREPE-tiny fallback, and Android/iOS audio shims (Phase 2).
