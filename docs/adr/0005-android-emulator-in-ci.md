# ADR 0005: Running the native tests on an Android emulator in CI

Status: Accepted, option B (Kelechi, 2026-11-22). Option A would have added a third-party GitHub Action, which the architecture doc forbids without an ADR; B needs none.

## Context

The `android` job in `.github/workflows/dsp.yml` builds `libintono.so` for three ABIs (arm64-v8a, armeabi-v7a, x86_64) with the NDK that ships on the runner image and checks the result (symbols, `libc++_shared.so`, 16 KB `LOAD` alignment). It never executes the code on Android. The host build runs the unit tests (68 plus the real-time safety binary), ASan, TSan and the accuracy harness; nothing runs against bionic.

That matters more since ADR 0004: the note tracker now calls `sin`, `cos`, `log` and `log1p` in a fit whose result depends on ties and on floating-point details, and bionic's libm is not glibc's. The C++/Python parity (note count, `midi`, `frames` identical on 420 clips; times, means, std within print resolution) was measured against glibc only. Android and iOS jobs are also still unverified from the authoring environment (the NDK download is blocked there), so the first real CI run is the first time they execute at all.

## Options

**A. `reactivecircus/android-emulator-runner`** (third-party action). One `uses:` line starts an emulator, runs a script, and handles boot waiting and caching. Adds a third-party dependency with code running in CI with the repository's token. Mitigation: pin to a commit SHA, give the job read-only permissions, no secrets in that job.

**B. The SDK tools already on the `ubuntu-24.04` image** (`sdkmanager`, `avdmanager`, `emulator`, `adb`), driven from the workflow script: enable KVM, install one x86_64 system image, create an AVD, start the emulator headless (`-no-window -no-audio -gpu swiftshader_indirect`), wait for boot, `adb push` the NDK-built test binary, run it with `adb shell`, collect the exit code. No new vendor: the system image comes from Google's SDK repository, the same source as the NDK already in use. More shell to maintain and a known flakiness point (boot waiting).

**C. No emulator.** Keep the build-and-inspect job. Cheapest, and leaves bionic and Android runtime behaviour untested.

## Decision (option B, accepted)

Add an `android-test` job that builds `intono_tests` (without the `--wrap` real-time test, which depends on glibc symbols) with the NDK for `x86_64` and runs it on an API 34 x86_64 emulator using option B. Everything is pinned: system image package name, emulator and platform-tools versions come from `sdkmanager` with explicit versions. The job uploads the test log. It does not replace the ARM build job; arm64 is not run (it is software-emulated and slow on x86 runners), so NEON paths stay unexecuted. `INTONO_BUILD_TESTS` already builds the gtest suite; no source change.

If B proves too flaky to keep green (more than one unexplained boot failure in ten runs), fall back to A through a new ADR that names the pinned commit, not by editing this one.

## Consequences

- bionic libm differences in the note tracker show up as test failures instead of in users' hands. The parity numbers in ADR 0004 are still glibc-only until this job exists and passes.
- About 8 to 12 CI minutes per run, plus a system-image download of roughly 1 GB (cacheable).
- arm64 and real devices are not covered. Real-device latency and the audio path belong to Phase 2.
- This ADR changes nothing in the C API or the product.
