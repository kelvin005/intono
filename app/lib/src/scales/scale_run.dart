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

  /// The grade of the most recently played note that took a place in the scale; null before the first. A far stray note (an extra)
  /// does not change it; a wrong note (it took the place of the note due) shows red at once.
  Grade? get latestGrade {
    final r = _graded;
    if (r == null) return null;
    GradedNote? latest;
    for (final g in r.notes) {
      if (g.heard != null && (latest == null || g.heard!.tStart > latest.heard!.tStart)) latest = g;
    }
    if (latest == null) return null;
    return latest.isWrong ? Grade.red : latest.grade;
  }

  /// A confident suggestion to regrade this run at another octave or as another scale, or null (see [suggestScale]).
  ScaleSuggestion? suggestion(ScaleLibrary library) => suggestScale(scale, _played, library, config);

  /// The same notes graded against [other] (a suggestion's scale).
  ScaleResult regrade(ScaleDef other) => gradeScale(other, _played, config);

  /// The position in the scale of the note due next: after the last one that took a place (played or wrong); 0 before the first.
  int get dueIndex {
    final r = _graded;
    var last = -1;
    if (r != null) {
      for (final g in r.notes) {
        if (g.heard != null) last = g.index;
      }
    }
    return last + 1 >= scale.notes.length ? scale.notes.length - 1 : last + 1;
  }

  /// The live grade of a pitch sounding now ([midi] and [cents] from a frame): against the note due, or the one after it (a new note
  /// can start before the previous summary has arrived), whichever is nearer, with the same thresholds as the grades. Far from both:
  /// 🔴 (a wrong note).
  Grade liveGrade(int midi, double cents) {
    final due = dueIndex;
    var best = double.infinity;
    for (final i in [due, due + 1]) {
      if (i >= scale.notes.length) continue;
      final c = ((midi - scale.notes[i].midi) * 100.0 + cents).abs();
      if (c < best) best = c;
    }
    return best <= config.greenCents ? Grade.green : (best <= config.yellowCents ? Grade.yellow : Grade.red);
  }

  /// True once the last note of the scale (the low tonic after the descent) has been played.
  bool get complete => _graded != null && _graded!.notes.last.heard != null;

  ScaleResult result() => _graded ?? gradeScale(scale, const [], config);
}
