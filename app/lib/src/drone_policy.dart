/// Drone policy (ADR 0009, Kelechi 2026-11-23), the Dart twin of the Kotlin DronePolicy: off by default and on by default only with
/// headphones; the user can override; playing on the speaker shows a warning (the drone leaks into the microphone until Phase 3).
class DronePolicy {
  static const String speakerWarning = 'Use headphones for accurate results';

  /// [userChoice] is null until the user touches the switch.
  static ({bool play, bool warnSpeaker}) decide(bool? userChoice, bool headphones) {
    final play = userChoice ?? headphones;
    return (play: play, warnSpeaker: play && !headphones);
  }
}
