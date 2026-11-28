import 'dart:math' as math;

import '../db/practice_stats.dart';
import '../scales/grader.dart';
import '../scales/grading_config.dart';

/// One cell of the finger-level heatmap (architecture doc, "Coaching"): every graded note played on one (string, finger, placement).
/// Computed from `graded_notes`, not from the caches, so a change of thresholds or mapping shows at once (ADR 0015 decision 4).
class HeatCell {
  const HeatCell({
    required this.string,
    required this.finger,
    required this.placement,
    required this.count,
    required this.played,
    required this.sessions,
    required this.meanCents,
    required this.meanAbsCents,
    required this.stdCents,
  });

  final String string; // 'G', 'D', 'A' or 'E'
  final int finger; // 0 open, 1 to 4
  final String? placement; // 'low', 'high' or null
  final int count, played, sessions;
  final double? meanCents, meanAbsCents, stdCents; // null if every note was missed

  int get missed => count - played;

  /// The cell's colour: the grader's thresholds on the mean absolute error; null (no colour) if nothing was played.
  Grade? grade(GradingConfig cfg) => meanAbsCents == null ? null : gradeOfCents(meanAbsCents!, cfg);

  String get where {
    final f = finger == 0 ? 'open' : '${ordinal(finger)} finger${placement == null ? '' : ' ($placement)'}';
    return '$string string, $f';
  }

  /// "A string, 3rd finger (high): average +15¢ over 12 notes in 4 sessions".
  String describe() {
    final notes = played == 1 ? '1 note' : '$played notes';
    final sess = sessions == 1 ? '1 session' : '$sessions sessions';
    if (meanCents == null) return '$where: missed every time ($count ${count == 1 ? 'note' : 'notes'})';
    return '$where: average ${signedCents(meanCents!)} over $notes in $sess';
  }
}

String ordinal(int n) => switch (n) { 1 => '1st', 2 => '2nd', 3 => '3rd', _ => '${n}th' };

/// "+15¢", "−2¢" (a true minus sign), "0¢".
String signedCents(double c) {
  final r = c.round();
  if (r > 0) return '+$r¢';
  if (r < 0) return '−${-r}¢';
  return '0¢';
}

const _stringOrder = {'G': 0, 'D': 1, 'A': 2, 'E': 3};
int _placementOrder(String? p) => switch (p) { 'low' => 0, null => 1, 'high' => 2, _ => 3 };

/// Groups (session id, graded note) pairs into heatmap cells, in fingerboard order: string G D A E, then finger, then low, natural,
/// high. The cents statistics use the played notes only (population standard deviation).
List<HeatCell> heatmapOf(Iterable<(String, StoredNote)> rows) {
  final groups = <String, List<(String, StoredNote)>>{};
  for (final r in rows) {
    final n = r.$2;
    groups.putIfAbsent('${n.string}|${n.finger}|${n.placement ?? ''}', () => []).add(r);
  }
  final cells = <HeatCell>[];
  for (final g in groups.values) {
    final first = g.first.$2;
    final cents = [for (final r in g) if (r.$2.cents != null) r.$2.cents!];
    double? mean, meanAbs, std;
    if (cents.isNotEmpty) {
      mean = cents.reduce((a, b) => a + b) / cents.length;
      meanAbs = cents.map((c) => c.abs()).reduce((a, b) => a + b) / cents.length;
      final m = mean;
      std = math.sqrt(cents.map((c) => (c - m) * (c - m)).reduce((a, b) => a + b) / cents.length);
    }
    cells.add(HeatCell(
      string: first.string,
      finger: first.finger,
      placement: first.placement,
      count: g.length,
      played: cents.length,
      sessions: {for (final r in g) r.$1}.length,
      meanCents: mean,
      meanAbsCents: meanAbs,
      stdCents: std,
    ));
  }
  cells.sort((a, b) {
    final s = (_stringOrder[a.string] ?? 9).compareTo(_stringOrder[b.string] ?? 9);
    if (s != 0) return s;
    final f = a.finger.compareTo(b.finger);
    return f != 0 ? f : _placementOrder(a.placement).compareTo(_placementOrder(b.placement));
  });
  return cells;
}
