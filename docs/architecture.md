# Violin Intonation Trainer — Production Architecture

Nov 21, 2026 · @kelechi

> **v1 scope changed (2026-11-27, ADR 0012):** no accounts, no backend, no sync; Pro is a one-time unlock through Play Billing and the
> App Store. The sections on the backend, sync, remote config, subscriptions and Phase 4 are kept as written for history and are **not
> built for v1**; ADR 0012 lists them.

## Overview and principles

The app scales to millions of users because all real-time audio work runs on the phone; the backend only stores small practice summaries and handles accounts and subscriptions. Working name: **Intono** (rename freely).

**What it does (v1):** real-time intonation feedback for violin (later viola and cello). It shows the note, cents sharp or flat, a drone to play against, graded scales, and a per-note heatmap of habitual errors.

**Out of scope for v1:** double stops (polyphonic detection), bowing analysis, video, social features, teacher dashboards.

### Non-negotiable principles

1. **On-device DSP.** Audio never leaves the phone by default. The real-time path has zero network calls, so server load and latency cannot cause lag.
2. **Offline-first.** Every v1 feature works with no internet. Sync is opportunistic and batched.
3. **Server off the hot path.** The backend serves accounts, entitlements, sync and content. It can be fully down and practice still works.
4. **Real-time audio rules.** The audio thread never allocates memory, takes locks, logs, or calls into Dart, Kotlin or Swift.
5. **One DSP core, two platforms.** A single C++ library serves Android and iOS and is the only place pitch logic lives.
6. **Boring, managed backend.** Stateless containers, managed Postgres, CDN. No custom infrastructure until the metrics demand it.
7. **Measured accuracy.** No DSP change merges without passing the accuracy harness (see Testing).

## System diagram

&#91;embedded content: system architecture · phone and cloud\]

Mic audio flows left to right through the DSP core to the screen with no network hop; only small session summaries travel down to the cloud.

## Mobile client

The client is a Flutter app over a shared C++ DSP core, with thin native audio shims per platform.

| Layer | Technology | Responsibility |
| --- | --- | --- |
| UI | Flutter 3.x, Dart, Riverpod for state | Screens, meter rendering at 60/120 fps, navigation |
| Bridge | `dart:ffi` + a shared-memory ring buffer | Passes pitch frames from C++ to Dart without copies or callbacks on the audio thread |
| DSP core | C++20 library `libintono` (CMake) | Pitch, vibrato, onsets, cents, drone synthesis |
| Audio I/O Android | Oboe (AAudio, OpenSL fallback) | Low-latency mic capture, drone output |
| Audio I/O iOS | AVAudioEngine / Audio Unit (RemoteIO) | Low-latency mic capture, drone output |
| Local DB | SQLite via `drift` | Sessions, note stats, sync queue |
| ML (optional) | TFLite (Android), Core ML (iOS) | CREPE-tiny fallback for low-confidence frames |

### Threading model

- **Audio thread (real-time, OS-owned):** receives mic buffers, runs the DSP core, writes results into a lock-free single-producer/single-consumer ring buffer. Hard budget: finish each callback in under 50% of the buffer duration.
- **UI isolate (Dart):** polls the ring buffer on each vsync via `Ticker`, smooths values for display, renders. Never blocks on audio.
- **Background isolate (Dart):** writes session data to SQLite, runs sync, computes heatmap aggregates.

### Audio thread rules (enforced in code review)

- No `malloc`/`new`, no `std::vector` growth, no `std::string` building. Preallocate everything at session start.
- No mutexes, no syscalls, no logging, no file or network I/O.
- Use `std::atomic` and the ring buffer only for cross-thread data.
- Request exclusive/low-latency mode: Oboe `PerformanceMode::LowLatency`, `SharingMode::Exclusive`; iOS `AVAudioSession` mode `.measurement`, preferred IO buffer 5 ms.
- Disable OS voice processing (AGC, noise suppression, echo cancellation): they distort pitch. Use `InputPreset::Unprocessed` on Android where supported.

### Device support

- Android 8.0+ (API 26), arm64-v8a and armeabi-v7a. Must run smoothly on low-end devices (2 GB RAM, e.g. Tecno, Infinix, itel).
- iOS 15+.
- Measure round-trip latency per device on first launch and store a calibration offset.

## DSP pipeline

The DSP core turns mic audio into a stream of `(note, cents, confidence, vibrato)` frames every 5.3 ms, with under 50 ms end-to-end latency.

### Pipeline stages

1. **Capture:** native sample rate (48 kHz typical, 44.1 kHz accepted; the core is rate-agnostic). Device buffer 128 to 256 frames.
2. **Preprocess:** DC blocker; 2nd-order Butterworth high-pass at 150 Hz; low-pass at 4 kHz; adaptive noise gate (noise floor learned in the first 500 ms, gate opens at floor + 10 dB).
3. **Pitch detection:** YIN with cumulative mean normalised difference, FFT-accelerated (pffft). Window 1024 samples (21 ms at 48 kHz), hop 256 samples (5.3 ms), search range 180 to 3200 Hz, threshold 0.12, parabolic interpolation for sub-sample lag. Confidence = 1 minus the normalised difference at the chosen lag.
4. **Octave guard:** reject a jump to roughly 2x or 0.5x the last stable pitch unless confidence is above 0.9 for 3 consecutive frames. Violin harmonics cause this error more than any other.
5. **ML fallback (optional, behind a flag):** when confidence stays below 0.6, run CREPE-tiny on the background thread and use its estimate for display only.
6. **Smoothing and vibrato:** keep a 250 ms pitch contour. Detect vibrato as a 4 to 8 Hz oscillation with 10 to 100 cents extent. Display the centre pitch as the midpoint of peak and trough, averaged over the last full cycle; a peak counts only after an 8¢ swing back; once vibrato is established the last centre is held for up to 250 ms; with no vibrato, fall back to the 150 ms median (ADR 0001; synthetic result 0.65¢, 1.03¢ at 10 dB SNR). Report vibrato rate and width as extra outputs.
7. **Note segmentation:** an onset is an RMS rise over 6 dB, or a pitch move over 50 cents held for 30 ms. A note is a segment with stable pitch for at least 80 ms. Note boundaries for summaries come from a fixed-lag note HMM (lag set so summary delay stays at or under 350 ms; currently 40 frames) run on the pitch track, so a legato step of 60¢ or more is found even inside wide vibrato (see the note-HMM ADR); the live display keeps its own zero-lag path. Each finished note emits a summary: target note, mean cents, cents spread, duration.
8. **Cents and grading:** compare against the target pitch in the selected tuning system.

### Cents calculation

```latex
\text{cents} = 1200 \cdot \log_2\left(\frac{f_{\text{measured}}}{f_{\text{target}}}\right), \qquad f_{\text{ET}}(n) = f_{A4} \cdot 2^{(n-69)/12}
```

### Tuning systems

| Mode | How target pitch is set | Who needs it |
| --- | --- | --- |
| Equal temperament (default) | Formula above, A4 adjustable 415 to 466 Hz (default 440; 442 common in Europe) | Beginners, playing with piano |
| Just intonation | Ratios to the tonic or drone: 1, 16/15, 9/8, 6/5, 5/4, 4/3, 45/32, 3/2, 8/5, 5/3, 9/5, 15/8 | Scale and drone practice, string quartets |
| Pythagorean | Stacked pure fifths (3/2) from the tonic | Melodic playing, matching open strings tuned in fifths |

Supported playing range: G3 (196 Hz) to E7 (2637 Hz).

### Drone interference

The phone speaker's drone leaks into the mic. v1: prompt for headphones, and when on speaker apply notch filters at the drone's fundamental and first 6 harmonics. v1.1: replace notches with an NLMS adaptive canceller (256 taps) using the generated drone signal as the reference, so unison notes with the drone are still detected.

### Latency budget

| Stage | Budget |
| --- | --- |
| Mic hardware + OS input buffer | 5 to 20 ms |
| Analysis window fill (effective) | about 11 ms |
| DSP compute per hop | under 1 ms |
| Ring buffer to UI frame | up to 16 ms |
| Display scan-out | up to 16 ms |
| **Target total** | **under 50 ms p95; under 80 ms on low-end Android** |

### Accuracy and performance targets

- Gross pitch error (wrong note or octave) under 1% of frames on stable notes.
- Mean absolute error under 3 cents on stable notes without vibrato; under 5 cents on vibrato centre pitch.
- CPU under 10% of one core on a mid-range phone; under 20% on low-end.
- Battery: under 8% per 30-minute session on a mid-range phone.

## Feature modules

Each feature is a Flutter module that consumes the same DSP frame stream; none needs the network.

| Module | What the player sees | Built on | Tier |
| --- | --- | --- | --- |
| Live meter | Note name, needle, cents (green within ±5¢, yellow ±5 to 15¢, red beyond), vibrato indicator | Frame stream | Free |
| Tuner | Open-string mode G3, D4, A4, E5 with auto-detect | Frame stream | Free |
| Drone | Sustained tone on any note, sine or rich string timbre, volume, octave | C++ additive synth on the audio thread | Free (1 timbre), Pro (all) |
| Scale grader | Pick key and scale (major, minors, 1 to 3 octaves); each note graded on completion; final score % | Note summaries + target sequence | Pro |
| Intonation heatmap | Fingerboard view: each note coloured by average cents error over the last 30 days | Aggregated note stats | Pro |
| Progress | Daily practice minutes, streaks, scale accuracy trend | Session table | Free (7 days), Pro (all time) |
| Settings | A4 reference, tuning system, instrument (violin first; viola, cello later), thresholds | Local prefs + remote config | Free |

### Scale grading rules

- A note counts when it is held 150 ms or more; the grade uses the mean pitch over the whole note, not the live display value (ADR 0001).
- Missed or wrong notes are matched with an edit-distance alignment against the target scale, so one wrong note does not shift every later grade.
- Score = share of notes within ±10¢ (thresholds in remote config so they can be tuned without a release).

### Monetisation hooks

- Entitlements come from the subscription provider and are cached locally with an expiry, so Pro features keep working offline for up to 14 days.
- Paywall copy and prices are remote-configured for A/B tests.

### Coaching: "the violin coach that tells you which finger to fix"

This is the product's core promise and the centre of Phase 3; the scale grader is its main data source.

- **Note to finger and string:** each graded note is mapped to the string and finger that played it. In scale mode the scale's fingering is known. In free play, assume first position with the standard beginner fingering. Mapping rules live in data files so viola and cello can be added later.
- **Finger-level heatmap:** errors are aggregated per string and finger (e.g. "A string, 3rd finger: average +15¢ over 12 sessions"), not just per note name.
- **Advice in words:** after each run, at most one or two short tips chosen from rules: the most consistent error first, then a suggested exercise ("Your 3rd finger on A is often 15¢ sharp. Try A major slowly with the drone."). Tips are templates with filled-in values, not free-form AI text, so they are predictable and testable.
- **Spoken summary (optional):** the same tips read aloud with the phone's built-in, offline text-to-speech, only after a run ends, never while playing. The microphone is paused while the app speaks so the engine never grades the app's own voice. On by default only with headphones; a setting turns it on or off.
- **Thresholds** for "often" and "sharp" sit in remote config so they can be tuned with teacher feedback without a release.

### Practising without staring at the screen

Players watch their fingers and their music, not a phone, so every practice mode must work at a glance or with no looking at all.

| Mode | How feedback reaches the player | Needs looking? |
| --- | --- | --- |
| Glance view | Whole screen turns green, yellow or red; phone sits on the music stand and is read in peripheral vision | Glance only |
| Drone | Out-of-tune notes "beat" (wobble) against the drone, so the ear learns to hear errors | No |
| Play, then review | Scale mode records the run silently; afterwards shows each note coloured, with tap-to-replay of the student's own audio | No, until the end |
| Heatmap | Patterns across days ("3rd finger flat on A string") | Only between sessions |

### Match my A

In the tuner and in settings, the player plays or plays back an A; the app measures it (e.g. 443.2 Hz) and sets it as the A4 reference for all modes. Covers orchestras at 442 Hz, baroque at 415 Hz, and playing along with a piano or recording. Phase 3.

## Local data and sync

The phone is the source of truth for practice data; the server holds a synced copy for backup, multi-device use and analytics.

### Local schema (SQLite via drift)

| Table | Key columns | Notes |
| --- | --- | --- |
| `sessions` | `id` (UUIDv7, client-generated), `started_at`, `ended_at`, `mode`, `instrument`, `a4_hz`, `tuning`, `key`, `scale`, `score`, `device_id`, `updated_at` | Immutable once ended (append-only) |
| `note_stats` | `session_id`, `midi_note`, `count`, `mean_cents`, `mean_abs_cents`, `std_cents`, `total_ms` | One row per note per session; feeds the heatmap |
| `settings` | `key`, `value`, `updated_at` | Last-write-wins by `updated_at` |
| `outbox` | `id`, `entity`, `entity_id`, `op`, `attempts`, `next_attempt_at` | Pending sync items (outbox pattern) |
| `entitlement_cache` | `tier`, `expires_at`, `signature` | Offline Pro access, 14-day grace |

Raw audio is never stored. The only exception is an opt-in "send a debug clip" button: max 10 seconds, explicit consent each time, deleted from the server after 30 days.

### Sync protocol

- **Push:** `POST /v1/sync/push` with up to 100 outbox items per batch, gzip. Every item carries its client UUID, so retries are idempotent (server upserts on `id`).
- **Pull:** `GET /v1/sync/pull?cursor=<opaque>` returns changes from other devices since the cursor; the client stores the new cursor.
- **Conflicts:** sessions and note stats are append-only, so they cannot conflict. Settings use last-write-wins on server-assigned timestamps.
- **Triggers:** session end, app going to background, and a periodic job every 6 hours (WorkManager on Android, BGTaskScheduler on iOS). Wi-Fi not required: a typical push is under 5 KB.
- **Backoff:** exponential with full jitter, 2 s base, 1 h cap. After 10 failures the item stays queued and the app shows a quiet "not synced" badge in settings, never in the practice screen.
- **Account deletion:** the client wipes local data; the server hard-deletes within 30 days (see Security).

## Backend

The backend is a stateless Go API on AWS that peaks around 300 requests per second at 1 million monthly users, so it has 10x to 50x headroom on modest hardware.

### Components (AWS)

| Component | Choice | Why |
| --- | --- | --- |
| DNS, edge, WAF | Route 53, CloudFront, AWS WAF | TLS at the edge, rate limiting, bot filtering |
| API | Go 1.23+ (`chi` router, `pgx`), container on ECS Fargate, 3 to 30 tasks across 3 AZs | Small memory, fast cold start, no servers to patch |
| Workers | Same Go binary in `worker` mode on Fargate, fed by SQS | Webhooks, account deletion, rollups |
| Database | Amazon Aurora PostgreSQL (Multi-AZ) + RDS Proxy; 1 read replica | Managed failover, connection pooling |
| Cache | ElastiCache (Valkey/Redis), Multi-AZ | Rate limits, entitlement cache, hot config |
| Object storage + CDN | S3 + CloudFront | Scale and lesson JSON, ML model files, remote config, debug clips |
| Auth | Firebase Authentication (Sign in with Apple, Google, email link; anonymous first) | Free at this scale; API verifies JWTs against cached JWKS |
| Subscriptions | RevenueCat (App Store + Google Play) | Receipt validation, webhooks into our entitlements table |
| Product analytics | PostHog, sent directly from the client in batches | Keeps analytics traffic off our API |
| Crash reporting | Sentry (Flutter + native C++ symbols) | Catches crashes in the DSP core |

### API (REST, JSON, versioned under `/v1`)

| Method + path | Purpose |
| --- | --- |
| `GET /v1/me` | Profile, settings, entitlement |
| `POST /v1/sync/push` | Batched, idempotent upload of sessions and settings |
| `GET /v1/sync/pull?cursor=` | Changes since cursor, for other devices |
| `GET /v1/entitlements` | Current tier and expiry, signed |
| `POST /v1/webhooks/revenuecat` | Subscription events (signature-verified, queued to SQS) |
| `POST /v1/debug-clips` | Returns a pre-signed S3 upload URL (opt-in only) |
| `DELETE /v1/me` | Account deletion request |
| Static: `https://cdn.../config/v{n}.json` | Remote config, thresholds, paywall, feature flags |

All requests carry `Authorization: Bearer <Firebase JWT>`, `X-App-Version`, and `Idempotency-Key` on writes. Errors use RFC 9457 problem JSON. The OpenAPI spec in `api/openapi.yaml` is the contract; client and server stubs are generated from it.

### Server data model (Postgres)

| Table | Key columns | Notes |
| --- | --- | --- |
| `users` | `id`, `auth_uid` (unique), `created_at`, `country`, `age_band`, `deleted_at` | `age_band` only, never birth date |
| `devices` | `id`, `user_id`, `platform`, `model`, `latency_ms`, `last_seen_at` | Latency calibration per device |
| `sessions` | `id` (client UUID, PK), `user_id`, `started_at`, `mode`, `score`, `note_stats` (JSONB), `server_seq` (bigserial) | Partitioned monthly on `started_at`; `server_seq` drives pull cursors |
| `settings` | `user_id`, `key`, `value`, `updated_at` | Last-write-wins |
| `entitlements` | `user_id`, `tier`, `expires_at`, `source`, `updated_at` | Written only by the webhook worker |

Indexes: `sessions (user_id, server_seq)`, `sessions (user_id, started_at desc)`. Partitions older than 18 months are exported to S3 as Parquet and dropped.

### Capacity maths (planning assumptions)

| Quantity | Assumption | Result |
| --- | --- | --- |
| Monthly active users | 1,000,000 |  |
| Daily active users | 30% of MAU | 300,000 |
| API calls per DAU per day | 4 pushes + 4 pulls + 1 profile | 2.7M calls/day = 31 req/s average |
| Peak load | 10x average (evening peaks) | about 310 req/s |
| Capacity per Fargate task (1 vCPU) | 1,500 req/s for these endpoints (verify with load test) | 3 tasks already cover peak 14x |
| Sessions stored | 1.5 per DAU per day, about 1.5 KB each | about 0.7 GB/day, 250 GB/year |

Rough running cost at 1M MAU: about $2,000 to $3,000 per month (Aurora is the largest line). Validate with the AWS pricing calculator before launch.

### Infrastructure regions

Start in one region (`eu-west-1`, close to both Europe and Africa) with 3 AZs. Add a second region only if latency data or an SLO breach justifies it: the real-time path never touches the server, so API latency does not affect practice.

## Scaling and reliability

The design target is that no backend failure can stop someone practising; backend SLOs protect sync, sign-in and purchases.

### SLOs

| Signal | Target |
| --- | --- |
| Practice features available offline | 100% (by design) |
| Crash-free sessions | 99.8% or better |
| Audio glitch rate (xruns per session minute) | under 0.1 |
| End-to-end pitch latency | p95 under 50 ms (under 80 ms on low-end Android) |
| API availability | 99.9% monthly |
| API latency | p99 under 300 ms at the edge |
| Sync freshness | 99% of sessions on the server within 1 hour of ending (when online) |

### Scaling levers, in order

1. Horizontal autoscaling of API tasks on CPU (target 50%) and request count.
2. RDS Proxy connection pooling; keep each task's pool at 10 connections.
3. Redis cache for `/v1/me` and entitlements (60 s TTL, invalidated by the webhook worker).
4. Serve every static or config read from CloudFront, never the API.
5. Aurora read replica for analytics and admin queries.
6. Larger Aurora instance class. Shard by `user_id` only if write load exceeds a single writer, which these numbers do not predict below roughly 50M MAU.

### Failure modes

| Failure | Effect on users | Mitigation |
| --- | --- | --- |
| API or database down | None for practice; sync and sign-in paused | Outbox retries; cached entitlements (14 days) |
| Bad app release | Crashes or wrong pitch | Staged rollout 1%, 10%, 50%, 100%; remote kill switch per feature; DSP accuracy gate in CI |
| Bad config push | Wrong thresholds | Versioned config with schema validation; client falls back to last good version |
| Thundering herd after an outage | Retry storm | Full-jitter backoff; per-user rate limit at WAF and Redis |
| RevenueCat outage | Purchases delayed | Cached entitlement; webhook replay from RevenueCat dashboard |
| Region outage | Sync paused | Daily snapshots + point-in-time recovery (35 days); restore runbook tested quarterly |
| Audio route change (headphones, call) | Stream stops | Listen for route and interruption events; restart the stream in under 300 ms |

### Load testing

Before launch, run k6 against staging at 3x the projected peak (about 1,000 req/s) for 30 minutes, with a realistic mix: 45% push, 45% pull, 10% profile. Pass: p99 under 300 ms, error rate under 0.1%, no database CPU above 60%.

## Security and privacy

Many violin learners are children, so the app collects as little as possible and treats under-13 users as a separate, local-only mode.

### Children and age

- Neutral age gate on first launch ("What year were you born?" with no default), stored only as an age band.
- **Under 13 (under 16 where local law requires):** local-only mode. No account, no sync, no analytics identifiers, no third-party SDK data sharing, purchases only through the platform's family controls. A parent-managed account with verified consent is a later feature.
- Laws to review with a lawyer before launch: US COPPA, EU GDPR (Article 8), UK Age Appropriate Design Code, and Nigeria's Data Protection Act 2023. Also follow Apple and Google store policies for apps used by children.

### Data minimisation

- Audio is processed in memory and discarded. The microphone permission prompt says so in plain words.
- No contacts, location or advertising ID. No ad SDKs.
- Analytics events contain feature usage and anonymous IDs only; no free-text fields.

### Security controls

| Area | Control |
| --- | --- |
| Transport | TLS 1.2+ everywhere; HSTS; certificate pinning not used (avoids bricking on rotation) |
| Auth | Firebase JWT verified on every request (issuer, audience, expiry); 1 h token lifetime |
| Authorisation | Every query scoped by `user_id` from the token, never from the request body; tested in CI |
| Secrets | AWS Secrets Manager; no secrets in the app binary or repo; GitHub OIDC for CI deploys |
| Database | Encryption at rest (KMS); private subnets only; IAM auth via RDS Proxy |
| Input | Request size limit 256 KB; JSON schema validation from the OpenAPI spec |
| Webhooks | RevenueCat signature check; replay protection by event ID |
| Abuse | WAF rate limits (per IP) + Redis token bucket (per user) |
| Dependencies | Dependabot + `govulncheck` + `flutter pub outdated` in CI; SBOM per release |
| Client | Obfuscated Dart release builds; entitlement cache signed by the server |

### User rights

- Export: JSON download of all sessions from settings.
- Deletion: `DELETE /v1/me` queues a worker that hard-deletes rows and S3 objects within 30 days, then deletes the Firebase user. Required by both app stores.

## App Store submission (Apple)

The main App Review risks are the microphone, subscriptions and children; each has a fixed requirement below. Re-check the current App Review Guidelines before each submission, as Apple updates them.

### Microphone and audio session

- `NSMicrophoneUsageDescription` (Info.plist): "Intono listens to your violin to show whether each note is in tune. Audio is analysed on your phone and is never recorded or uploaded."
- `AVAudioSession` category `.playAndRecord`, mode `.measurement`, options `.defaultToSpeaker`. Warn when a Bluetooth route is active (adds latency).
- Do not declare the `audio` background mode in v1: practice stops when the app is backgrounded, and an unjustified background mode is a common rejection.
- Ask for mic permission only when the user first opens the meter, after a one-screen explanation, never at launch.

### Privacy

- **Privacy manifest** (`PrivacyInfo.xcprivacy`): declare required-reason APIs used by the app and confirm every SDK (Firebase, Sentry, RevenueCat, PostHog) ships its own manifest at the pinned version.
- **App Privacy label** in App Store Connect:

| Data type | Collected? | Linked to user | Used for tracking |
| --- | --- | --- | --- |
| Audio | No (processed on device only) | n/a | n/a |
| Email (if account created) | Yes | Yes | No |
| User ID | Yes | Yes | No |
| Purchase history | Yes | Yes | No |
| Product interaction (usage) | Yes | No | No |
| Crash and performance data | Yes | No | No |

- No tracking, so no App Tracking Transparency prompt and no IDFA.
- Export compliance: only standard HTTPS, so set `ITSAppUsesNonExemptEncryption` to `NO`.

### Accounts and subscriptions

- **Sign in with Apple** is required because Google sign-in is offered. Anonymous use stays the default.
- **In-app account deletion** must be available from settings (wired to `DELETE /v1/me`).
- **Paywall** must show price, billing period, free-trial length, auto-renewal terms, Restore Purchases, and links to Terms of Use and the Privacy Policy.
- Enrol in the App Store Small Business Program (lower commission while yearly proceeds stay under its threshold).

### Children

- Do **not** list in the Kids Category for v1: it bans third-party analytics and requires parental gates throughout. List under Music (primary) and Education (secondary).
- Age rating 4+. The in-app under-13 mode (see Security) handles younger users.
- Parental gate in front of the paywall and external links when the age band is under 13.

### Review readiness

- Add a **Demo mode** that plays a bundled violin recording through the engine, so a reviewer without a violin can see the meter, scale grader and heatmap work.
- Review notes: explain the mic use, how to reach Demo mode, and how to test Pro with a sandbox account.
- TestFlight external testers need a Beta App Review; budget 1 to 2 days.
- Screenshots and preview video at the sizes App Store Connect currently requires; v1 is iPhone-only (add iPad later to avoid extra screenshot sets and layout work).

### Submission checklist

- [ ] Apple Developer Program enrolment ($99/year; organisation enrolment needs a D-U-N-S number)
- [ ] Mic usage string and permission flow
- [ ] Privacy manifest and App Privacy label
- [ ] Sign in with Apple and in-app account deletion
- [ ] Paywall disclosures and Restore Purchases
- [ ] Demo mode and review notes
- [ ] Privacy Policy and Terms URLs live
- [ ] Small Business Program enrolment
- [ ] Screenshots, description, keywords, support URL

## Observability, CI/CD and infrastructure

Everything is defined in Terraform and shipped through GitHub Actions; nobody changes production by hand.

### Observability

- **Server:** OpenTelemetry traces and metrics from the Go API to CloudWatch (or Grafana Cloud). Structured JSON logs with a request ID; no personal data in logs.
- **Client:** Sentry for crashes (Dart + native C++ with uploaded symbols) and ANRs; on-device counters for audio xruns, measured latency, CPU % and confidence distribution, sent as one PostHog event per session.
- **Dashboards:** API RED metrics (rate, errors, duration), DB CPU and connections, sync lag, crash-free rate by app version, latency p95 by device model.
- **Alerts (PagerDuty or Opsgenie):** API 5xx over 1% for 5 min; p99 over 500 ms for 10 min; DB CPU over 80%; crash-free sessions below 99.5% on any version with more than 1,000 sessions.

### CI/CD (GitHub Actions)

| Pipeline | Steps |
| --- | --- |
| DSP core | Build with CMake for Linux, Android NDK, iOS; unit tests; sanitizers (ASan, UBSan, TSan); **accuracy harness gate** |
| Mobile | `flutter analyze`, unit + widget tests, integration tests on Firebase Test Lab device matrix; Fastlane builds; upload to TestFlight and Play internal track |
| Backend | `go vet`, `staticcheck`, `govulncheck`, unit + integration tests against Postgres in Docker; build image; push to ECR; deploy to staging; smoke tests; manual approval; blue/green deploy to prod via ECS + CodeDeploy |
| Infra | `terraform fmt`, `validate`, `plan` on pull request; `apply` on merge to `main` with approval |

### Environments

`dev` (local Docker Compose), `staging` (full AWS copy at small size), `prod`. Separate AWS accounts for staging and prod under AWS Organizations.

### Release process

- Mobile: staged rollout 1% to 10% to 50% to 100% over 7 days; halt automatically if crash-free rate drops below 99.5%.
- Backend: blue/green with automatic rollback on alarm; database migrations are backwards-compatible (expand, then contract) so old app versions keep working.
- Minimum supported app version enforced via remote config.

## Testing

Pitch accuracy is the product, so the DSP core has its own accuracy harness that blocks any merge that makes it worse.

### DSP accuracy harness (`tools/accuracy/`)

- A CLI that runs `libintono` offline over labelled audio and writes a JSON report. Scored with `mir_eval` in Python.
- **Synthetic set (generated, in repo):** sine and sawtooth tones across G3 to E7; vibrato 4 to 8 Hz at 10 to 80 cents; violin-like harmonic spectra; pink noise at 30, 20 and 10 dB SNR; deliberate detuning of ±1 to ±50 cents.
- **Public datasets (downloaded in CI, cached):** URMP violin tracks with note annotations, NSynth violin notes, Bach10 violin parts. Check each dataset's licence before commercial use.
- **Field set (later):** recordings from 5 or more violinists on 5 or more cheap phones in normal rooms, labelled by a trained ear.
- **Metrics:** raw pitch accuracy (within 50 cents), gross octave error rate, cents MAE on stable notes, cents MAE on vibrato centre, onset F1, voicing false-alarm rate, CPU time per hop.
- **Gate:** a pull request fails if any metric regresses by more than 0.5 percentage points or 0.5 cents against `main`.

### Other test layers

| Layer | Tooling | What it covers |
| --- | --- | --- |
| C++ unit | GoogleTest | Ring buffer, filters, YIN, cents maths, tuning tables |
| Real-time safety | Custom allocator hook + TSan in tests | Fails if the audio callback allocates or locks |
| Dart unit + widget | `flutter_test` | Grading, alignment, state, UI |
| Integration | `integration_test` on Firebase Test Lab | Mic stream with injected audio file, end-to-end note display |
| Latency | Loopback test app (speaker to mic) | Round-trip latency per device model |
| Backend | Go tests + Testcontainers Postgres | Sync idempotency, authorisation scoping, webhooks |
| Load | k6 | See Scaling |

### Device matrix (minimum before each release)

- Android low-end: a 2 GB RAM Tecno or itel phone on Android 10+.
- Android mid: Samsung Galaxy A-series, Infinix Note.
- Android high: Pixel 7 or newer.
- iOS: iPhone SE (2nd gen), iPhone 13, latest iPhone.
- One Bluetooth headset (expect high latency; warn the user).

## Repo structure

One monorepo keeps the DSP core, app, backend and infrastructure versioned together.

```
intono/
├── dsp/                    # C++20 core: libintono
│   ├── include/intono/     # public C API (intono.h) for FFI
│   ├── src/                # yin, filters, vibrato, onset, tuning, drone, ringbuffer
│   ├── tests/              # GoogleTest
│   └── CMakeLists.txt
├── app/                    # Flutter app
│   ├── lib/
│   │   ├── audio/          # FFI bindings (ffigen), stream controller
│   │   ├── features/       # meter, tuner, drone, scales, heatmap, progress, settings
│   │   ├── data/           # drift schema, repositories, sync engine
│   │   └── core/           # config, entitlements, analytics, theme
│   ├── android/            # Oboe shim (Kotlin + JNI), links libintono
│   ├── ios/                # AVAudioEngine shim (Swift), links libintono
│   └── integration_test/
├── server/                 # Go API + worker
│   ├── cmd/api/  cmd/worker/
│   ├── internal/           # auth, sync, entitlements, users, deletion
│   ├── migrations/         # SQL, expand/contract only
│   └── Dockerfile
├── api/openapi.yaml        # the contract; generates Go + Dart clients
├── infra/terraform/        # modules: network, ecs, aurora, redis, cdn, waf, observability
├── tools/accuracy/         # harness CLI + Python scoring + dataset fetch scripts
├── tools/loadtest/         # k6 scripts
├── docs/                   # this architecture, ADRs, runbooks
└── .github/workflows/      # dsp.yml, app.yml, server.yml, infra.yml
```

Key decisions get a short ADR in `docs/adr/` (context, decision, consequences) so later changes have a record of why.

## Build phases and instructions for Claude

Build in six gated phases over roughly 10 to 13 weeks; do not start a phase until the previous gate passes.

1. **Phase 0: Reference prototype (1 week).** Python with `librosa.pyin` and a plain YIN over URMP and NSynth violin audio. Output: baseline metrics report. Gate: cents MAE under 5 on stable notes.
2. **Phase 1: DSP core (2 to 3 weeks).** `libintono` in C++ with the C API below, the accuracy harness and a desktop CLI (`intono-cli file.wav`). Gate: all accuracy targets met; real-time safety test passes; CPU per hop under 1 ms on a laptop.
3. **Phase 2: Audio shims and live meter (2 weeks).** Android Oboe shim first, then iOS. Ring buffer to Flutter; meter UI at 60 fps. Gate: p95 latency under 50 ms on mid-range devices; no xruns in a 30-minute session.
4. **Phase 3: Features and local data (2 to 3 weeks).** Tuner, drone (with notch filtering), scale grader, drift database, heatmap, progress, settings, age gate. Gate: all features work in airplane mode.
5. **Phase 4: Backend (2 weeks).** Terraform staging, Go API, Firebase Auth, sync, RevenueCat webhooks, deletion worker, observability. Gate: integration tests green; k6 load test passes at 1,000 req/s.
6. **Phase 5: Hardening and launch (1 to 2 weeks).** Field test with 5+ violinists on cheap phones, privacy and legal review, store listings, staged rollout. Gate: crash-free 99.8% in beta; no open P0 or P1 bugs.

### DSP core C API (stable FFI boundary)

```c
typedef struct intono_engine intono_engine;

typedef struct {
  float sample_rate;      // e.g. 48000
  int   window_size;      // 1024
  int   hop_size;         // 256
  float a4_hz;            // 440.0
  int   tuning;           // 0 = ET, 1 = just, 2 = pythagorean
  float min_hz, max_hz;   // 180, 3200
} intono_config;

typedef struct {
  double t_sec;
  float  hz, confidence;
  int    midi_note;
  float  cents;           // vs target in current tuning
  float  vibrato_rate_hz, vibrato_width_cents;
  int    is_voiced, is_onset;
} intono_frame;

// One finished note (ADR 0003). Stats exclude the first 4 and last 3 frames.
typedef struct {
  double t_start, t_end;
  int    midi_note;
  float  mean_cents, std_cents;
  float  vibrato_rate_hz, vibrato_width_cents; // 0 if none
  float  mean_confidence;
  int    frame_count;
} intono_note;

intono_engine* intono_create(const intono_config* cfg);   // allocates everything
void  intono_process(intono_engine*, const float* in, int n);  // audio thread, RT-safe
int   intono_read_frames(intono_engine*, intono_frame* out, int max); // UI thread
int   intono_read_notes(intono_engine*, intono_note* out, int max);   // UI/background thread; 64-entry ring
void  intono_set_tonic(intono_engine*, int midi_note);       // for just/pythagorean
void  intono_drone_set(intono_engine*, int midi_note, float gain, int timbre);
void  intono_drone_render(intono_engine*, float* out, int n); // audio thread, RT-safe
void  intono_destroy(intono_engine*);
```

### Instructions for Claude (paste with this doc)

- Work phase by phase in the order above. At the end of each phase, report the gate metrics and stop for review.
- Start with `dsp/` and `tools/accuracy/`. Write tests before or alongside each DSP component.
- Follow the audio thread rules strictly. Add a test that fails if `intono_process` or `intono_drone_render` allocates or locks.
- Treat `api/openapi.yaml` and the C API as contracts: change them only with an ADR.
- Do not add services, languages or vendors that this doc does not name without an ADR and my approval.
- Ask me before deciding: app name, final auth provider, AWS region, and any licence question about datasets.
- Deliver complete file contents, not diffs. Keep each module's README current.
- Never log or upload audio, and never add analytics to under-13 mode.
