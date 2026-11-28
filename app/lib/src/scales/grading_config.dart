import 'dart:convert';

/// Scale grading thresholds (ADR 0011). In v1 they come from a file bundled with the app (assets/config/grading.json; no remote config,
/// ADR 0012). The defaults here are the same values, so a missing or older file still grades the same way.
class GradingConfig {
  const GradingConfig({this.greenCents = 5, this.yellowCents = 15, this.minNoteMs = 80, this.mergeGapMs = 120, this.mergeMaxCentsDiff = 25, this.neighbourCents = 40});

  /// |cents| at or below this: 🟢.
  final double greenCents;

  /// |cents| at or below this (and above [greenCents]): 🟡. Beyond: 🔴.
  final double yellowCents;

  /// Notes shorter than this are not graded. 80 ms (Kelechi, 2026-11-27; the architecture doc's 150 ms marked fast semiquavers missed),
  /// just above the ADR 0004 glitch rule's 12 frames (64 ms).
  final double minNoteMs;

  /// Consecutive notes of the same pitch with a gap up to this are one note split in two (merged before grading).
  final double mergeGapMs;

  /// ... and with mean pitches within this many cents of each other (pieces of one note have nearly the same pitch).
  final double mergeMaxCentsDiff;

  /// ADR 0018 note: a note labelled as the expected note but more than this many cents from it also shows the nearest semitone
  /// ("sounds closer to B"; Kelechi, 2026-11-28).
  final double neighbourCents;

  static const supportedFormat = 1;

  factory GradingConfig.fromJsonString(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['format'] != supportedFormat) throw FormatException('unsupported grading config format ${j['format']}');
    const d = GradingConfig();
    double v(String k, double dflt) => (j[k] as num?)?.toDouble() ?? dflt;
    final c = GradingConfig(
      greenCents: v('grade_green_cents', d.greenCents),
      yellowCents: v('grade_yellow_cents', d.yellowCents),
      minNoteMs: v('min_note_ms', d.minNoteMs),
      mergeGapMs: v('merge_gap_ms', d.mergeGapMs),
      mergeMaxCentsDiff: v('merge_max_cents_diff', d.mergeMaxCentsDiff),
      neighbourCents: v('neighbour_cents', d.neighbourCents),
    );
    if (!(c.greenCents > 0 && c.yellowCents >= c.greenCents && c.minNoteMs >= 0 && c.mergeGapMs >= 0 && c.mergeMaxCentsDiff >= 0 && c.neighbourCents >= c.yellowCents)) {
      throw FormatException('inconsistent grading thresholds: $text');
    }
    return c;
  }
}

/// Where the thresholds come from: one interface, so a different source can replace the bundled file without touching the grader.
abstract class GradingConfigSource {
  Future<GradingConfig> load();
}
