# ADR 0017: Spoken summary after a run (Phase 3)

Status: **Proposed** (2026-11-28). It adds platform speech on both platforms and a setting, so it needs Kelechi's "merge". The questions
are at the end.

## Context

The architecture doc ("Coaching") asks for these:
- the run's tips read aloud with the phone's built-in, offline text-to-speech;
- only after a run ends, never while playing;
- the microphone paused while the app speaks, so the engine never grades the app's own voice;
- on by default only with headphones, with a setting to turn it on or off.

No new vendor or package (CLAUDE.md): the platforms' own speech engines are reached through a method channel, as the audio is.

## Decision (proposed)

1. **Engines.**
   - **Android:** `android.speech.tts.TextToSpeech` (the system engine). When the device language has a voice that does not need the
     network, that voice is used; otherwise the engine's default voice. The manifest declares the `TTS_SERVICE` query that Android 11
     and later require.
   - **iOS:** `AVSpeechSynthesizer` with the device language's voice. iOS voices are on the device.
   - Channel `intono/speech`: `speak(text)` returns whether speech started; `stopSpeaking`.
2. **When.** Speech starts only on the review screen, after the run's capture has ended:
   - Android stops the input stream at freeze (ADR 0013).
   - iOS stops the session's engine at freeze (#46).
   - Without an armed ring, the session is closed.
   So **the microphone is already off whenever the app speaks**. The screen asks for speech only after it has frozen or stopped
   capture, and a test checks that order.
3. **What.** One utterance: the score and counts, then the tips (ADR 0016). Text is made speakable: "¢" becomes "cents" and the minus
   sign becomes "minus".
   - Example: "Score 87 percent. 10 green, 3 yellow, 2 red, 0 missed. Your 3rd finger on A is often 15 cents sharp. Play F major, 1
     octave slowly with the drone."
4. **Stopping.** Speech stops when:
   - a replay starts (they would talk over each other);
   - the review ends: leaving it, Play again, the app going to the background, or the screen closing.
5. **Setting.** `spoken_summary` in the `settings` table, one of three values:
   - `auto` (the default): speak only when headphones are connected;
   - `on`;
   - `off`.
   The Settings screen cycles through them.
6. **Tests first:**
   - the speakable text;
   - the policy (each setting, with and without headphones);
   - the screen: speech after capture ends, never before; none when off; stopped by replay, leaving, background and close;
   - the settings toggle.
   The native glue is verified by CI's builds; hearing it needs Kelechi's phone.

## Questions for Kelechi

1. With the speaker (no headphones) the default is silent. Is `auto` the right default, as the doc says?
2. Should the score be spoken, or only the tips?
3. Device language: tips are English-only in v1, so should speech always use an English voice?
