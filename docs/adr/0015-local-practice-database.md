# ADR 0015: The local practice database (Phase 3 item 5)

Status: **Accepted** (Kelechi, 2026-11-27; his answers are below and are part of the decision). This is a new dependency with native
packaging on both platforms.

## Context

ADR 0011 item 5 says each graded scale note keeps its string, finger and placement from the scale data. A session's results then
become statistics per (string, finger, placement), stored on the phone (never audio). They feed the finger-level heatmap and the
templated tips that come later.

The architecture doc names SQLite via `drift` and the tables `sessions`, `note_stats` and `settings`. ADR 0012 removes `outbox`,
`entitlement_cache` and sync: there are no accounts and no backend. It also puts the practice database in Android Auto Backup and
iCloud backup.

Constraints from earlier ADRs:

- **iOS has no CocoaPods** (ADR 0010, Note 1). The SQLite library must arrive through Swift Package Manager or a Flutter build hook.
- **Android uses the shared STL** (ADR 0009, Amendment 1). Any bundled SQLite must not add a second `libc++_shared.so`, and the APK
  check must still pass: only `intono_*` and the JNI entry points are exported from the shim.
- **No Dart or Flutter in the Claude workspace.** Generated code is produced in CI and checked in, as with the ffigen bindings.

## Decision

1. **drift** on SQLite, with the version pinned in `pubspec.lock`.
   - SQLite comes from drift's own packaging: either `sqlite3_flutter_libs`, or `package:sqlite3`'s build hook, whichever works on
     SwiftPM-only iOS with the pinned Flutter.
   - The choice is made by CI, not by reading changelogs: the first PR must build and pass on `ios-app` (Simulator XCTest) and
     `android-emulator`, with a test that opens a database and writes to it on each.
   - If neither works without CocoaPods, use the iOS system `libsqlite3` through `package:sqlite3`, and the bundled library on Android
     only. That fallback gets an amendment to this ADR.
2. **Generated code** (`*.g.dart` from `drift_dev` + `build_runner`) is checked in. CI regenerates it and fails on any difference,
   printing the file, in the same step as the ffigen bindings. CI also keeps the lockfile check (`--enforce-lockfile`).
3. **Schema version 1:**

   | Table | Columns | Notes |
   |---|---|---|
   | `sessions` | `id` (UUIDv7 text, PK), `started_at`, `ended_at` (UTC ms), `mode` (`scale`), `instrument` (default `violin`), `a4_hz`, `tuning`, `scale_id`, `score_percent`, `green`, `yellow`, `red`, `missed`, `note_count` | Written once, when a run ends. Append-only. The totals are a cache of `graded_notes`. |
   | `graded_notes` | `session_id` (FK), `idx` (position in the scale), `midi_note`, `string` (`G`/`D`/`A`/`E`), `finger` (0-4), `placement` (`low`/`high`/null), `grade` (`green`/`yellow`/`red`/`missed`), `cents` (null if missed), `t_start`, `t_end` (seconds from the run's start; null if missed) | Every graded note of a run. PK (`session_id`, `idx`). The source of truth. |
   | `note_stats` | `session_id` (FK), `midi_note`, `string`, `finger`, `placement`, `count`, `green`, `yellow`, `red`, `missed`, `mean_cents`, `mean_abs_cents`, `std_cents`, `total_ms` | One row per (session, note, string, finger, placement). PK is those five keys. **A cache**, computed from `graded_notes`. |
   | `settings` | `key` (PK), `value`, `updated_at` | Local preferences. |

   Compared with the architecture doc, this drops `device_id` and the sync fields (ADR 0012). It keeps `instrument`, with default
   `violin`, so viola and cello need no migration. It adds string, finger, placement, the 🟢/🟡/🔴 counts (ADR 0011) and `graded_notes`.
4. **Every graded note is stored, and the totals are a cache.** `sessions` totals and `note_stats` are derived from `graded_notes`,
   so the heatmap and the tips can be recomputed if the thresholds (`grading.json`) or the scale's string/finger mapping change:
   - Rebuilding re-grades from the stored `cents` and fills the caches again.
   - A note that was **missed** stays missed.
   - Rebuilding re-maps string, finger and placement from `midi_note` and the scale's current data.

   Extra notes, frames and audio are never written. The replay buffer stays in RAM (ADR 0013). A run is about 30 rows, roughly 3 KB.
5. **Location and backup.** The file is `intono.sqlite`:
   - **iOS:** in Application Support. iCloud backs it up by default (ADR 0012).
   - **Android:** in the app's `databases/` directory. Auto Backup includes it by default, and a `data_extraction_rules.xml` /
     `full_backup_content.xml` lists it explicitly, so a later exclusion rule cannot drop it silently.
6. **Threading.** Writes run in drift's background isolate (`NativeDatabase.createInBackground`), so the UI thread never waits on
   disk. Reads for the results screen are a single query.
7. **Migrations.** Start at `schemaVersion` 1. Each later change bumps the version, and drift's schema dump and migration test cover it.
8. **Tests first.**
   - In-memory database tests (`NativeDatabase.memory()`, host `flutter test`):
     - a `ScaleResult` becomes the right `graded_notes` rows;
     - the caches equal a recomputation from `graded_notes`;
     - repeated notes on the same finger aggregate;
     - missed notes count but carry no cents;
     - sessions are append-only;
     - rebuilding the caches after a threshold change re-grades the stored cents;
     - "Clear history" leaves no rows behind;
     - the per-finger query that the heatmap will use.
   - A device-side smoke test on the Simulator and the emulator.

9. **Retention:** every session is kept forever.
   - **"Clear history"** in settings deletes every session (`sessions`, `graded_notes` and `note_stats`) in one transaction, after a
     confirmation dialog, then runs `VACUUM`.
   - `settings` is kept.

## Answers (Kelechi, 2026-11-27)

1. Drop `device_id` and the sync fields. Keep `instrument` (default "violin") to avoid a migration when viola and cello come.
2. Store every graded note (string, finger, placement, cents, grade, timing), plus per-session totals as a cache, so the heatmap can be
   recomputed if the thresholds or the mapping change.
3. Keep forever; add "Clear history" in settings.
