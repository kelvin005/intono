import '../engine_api.dart';
import 'grader.dart';
import 'grading_config.dart';
import 'scale.dart';

/// One run of a scale as the scale screen sees it (ADR 0011 item 4): the notes played so far, the grade of the latest one for the
/// glance view, whether the scale is finished, and the result. The whole run is re-graded on every batch (a scale is at most 43 notes).
class ScaleRun {
  ScaleRun(this.scale, this.config);

  final ScaleDef scale;
  final GradingConfig config;
  final List<Note> _played = [];
  ScaleResult? _graded;

  int get playedCount => _played.length;

  void addNotes(Iterable<Note> notes) {
    _played.addAll(notes);
    _graded = gradeScale(scale, _played, config);
  }

  /// The grade of the most recently played note that took a place in the scale; null before the first. A stray note played as the
  /// latest reads as a wrong note (red) until the next scale note arrives and re-grading makes it an extra.
  Grade? get latestGrade {
    final r = _graded;
    if (r == null) return null;
    GradedNote? latest;
    for (final g in r.notes) {
      if (g.played != null && (latest == null || g.played!.tStart > latest.played!.tStart)) latest = g;
    }
    return latest?.grade;
  }

  /// True once the last note of the scale (the low tonic after the descent) has been played.
  bool get complete => _graded != null && _graded!.notes.last.played != null;

  ScaleResult result() => _graded ?? gradeScale(scale, const [], config);
}
