# Intono: rules for Claude (and anyone else) working in this repository

Intono is a violin intonation trainer: a C/C++ DSP core (`dsp/`) behind a C API, and Flutter apps on Android and iOS (Phase 2 onward). Owner: Kelechi.

## Standing rules

- Work is phase-gated. Phase 1 (DSP core) is complete (tag `phase1-complete`). Phase 2 is the Android app, then iOS.
- `dsp/include/intono/intono.h` (the C API) and `openapi.yaml` are contracts. They change only by ADR.
- Deliver complete files, not diffs.
- Never log or upload audio. No analytics for users under 13. No new vendors or services without an ADR.
- Ask Kelechi before choosing: the app name, the auth provider, the AWS region, dataset licences.
- DSP freeze: DSP changes only in response to real-audio results or CI failures, each recorded in an ADR.
- Sealed-set protocol: seeds and hash pre-registered, frozen binary, one run, reported as measured, a failed set is never reused, parameters are never chosen on a sealed set.
- Real clip #1 is third-party material: internal testing only, gitignored (`testdata/real/`), never committed, shipped or put in the Project store. Datasets are test-only and never shipped.
- Failing tests first. An ADR for anything new. A PR only when its CI is green.

## Branches, pull requests and merging (permanent, Kelechi 2026-11-23)

- **Never push directly to `main`.** All changes go through a branch and a pull request. `main` changes only by merging a PR.
- **Claude may merge its own PR** (merge commit, not squash; delete the branch afterwards) when **all** of these hold:
  1. CI is fully green on the PR, and
  2. the PR changes **no ADR decision** (a new ADR, an accepted-ADR amendment, or a changed decision counts; a status note does not),
  3. **no public C API** (`intono.h`),
  4. **no gate or threshold**, and
  5. **no architecture-doc decision**.
- Any PR touching one of those needs Kelechi's explicit "merge" first.
- After a merge: pull `main`, confirm CI is green on `main`.
- **Tag milestones** (`phase1-complete`, `phase2-android-complete`, ...) when a phase gate passes.

## Tooling notes

- The Claude workspace has no Android SDK, no Flutter and no general internet access: Android and Flutter builds are verified by CI, and anything that needs a phone is verified by Kelechi on the device.
- `gh` works through a proxy: use the REST API (`gh api`) for pull requests; GraphQL is blocked. Pushing tags and deleting remote branches is currently refused by the proxy; Kelechi does those two steps.
- Pinned runner labels only (`macos-15`, `ubuntu-24.04`); never `*-latest`.
