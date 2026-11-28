import 'dart:convert';

import '../db/practice_stats.dart';
import '../heatmap/heatmap.dart' show ordinal;
import '../scales/grader.dart';
import '../scales/grading_config.dart';
import '../scales/scale.dart';

/// Coaching thresholds (ADR 0016), bundled as assets/config/coaching.json.
class CoachingConfig {
  const CoachingConfig({this.minNotes = 4, this.sharpCents = 10, this.oftenFraction = 0.6, this.missedTipMin = 2, this.maxTips = 2});

  /// Played notes on one (string, finger, placement) before it can get a tip.
  final int minNotes;

  /// The average error must be at least this many cents.
  final double sharpCents;

  /// At least this share of the played notes is off in the same direction by more than the green threshold.
  final double oftenFraction;

  /// Missed notes in the run before the "not heard" tip.
  final int missedTipMin;

  /// Tips per run.
  final int maxTips;

  static const supportedFormat = 1;

  factory CoachingConfig.fromJsonString(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (j['format'] != supportedFormat) throw FormatException('unsupported coaching config format ${j['format']}');
    const d = CoachingConfig();
    final c = CoachingConfig(
      minNotes: (j['min_notes'] as num?)?.toInt() ?? d.minNotes,
      sharpCents: (j['sharp_cents'] as num?)?.toDouble() ?? d.sharpCents,
      oftenFraction: (j['often_fraction'] as num?)?.toDouble() ?? d.oftenFraction,
      missedTipMin: (j['missed_tip_min'] as num?)?.toInt() ?? d.missedTipMin,
      maxTips: (j['max_tips'] as num?)?.toInt() ?? d.maxTips,
    );
    if (!(c.minNotes >= 1 && c.sharpCents > 0 && c.oftenFraction > 0 && c.oftenFraction <= 1 && c.missedTipMin >= 1 && c.maxTips >= 1)) {
      throw FormatException('inconsistent coaching thresholds: $text');
    }
    return c;
  }
}

class _Habit {
  _Habit(this.string, this.finger, this.placement, this.mean, this.share);
  final String string;
  final int finger;
  final String? placement;
  final double mean; // signed, cents
  final double share; // same-direction share of the played notes
}

const _stringOrder = {'G': 0, 'D': 1, 'A': 2, 'E': 3};

/// The tips after a run (ADR 0016), at most [CoachingConfig.maxTips], in rule order: habitual finger errors (most consistent first;
/// the first with an exercise), then missed notes, else "nothing to fix". [history] is (session id, graded note) of the last 30 days,
/// including [run] once it is saved; pass the run alone (storedNotesOf) when there is no history.
List<String> coachingTips({
  required List<(String, StoredNote)> history,
  required ScaleResult run,
  required ScaleLibrary library,
  required GradingConfig grading,
  CoachingConfig config = const CoachingConfig(),
}) {
  final tips = <String>[];
  // ADR 0018 note: notes labelled as the expected note but far from it come first: the worst one, and how many more.
  final far = [for (final g in run.notes) if (neighbourHint(g, grading) != null) g]
    ..sort((a, b) => b.cents!.abs().compareTo(a.cents!.abs()));
  if (far.isNotEmpty) {
    final w = far.first, h = neighbourHint(w, grading)!;
    final more = far.length - 1;
    tips.add('Your ${w.expected.name} was very ${h.sharp ? 'sharp' : 'flat'}, almost a ${h.name}.${more > 0 ? ' $more more were as far off.' : ''}');
  }
  final habits = _habits(history, grading, config);
  for (var i = 0; i < habits.length && tips.length < config.maxTips; i++) {
    final h = habits[i];
    final n = h.mean.abs().round();
    final dir = h.mean > 0 ? 'sharp' : 'flat';
    if (i > 0) {
      tips.add('Your ${_where(h)} is often $n¢ $dir too.');
    } else if (h.finger == 0) {
      tips.add('Your ${_where(h)} is often $n¢ $dir. Tune it against the drone before you play.');
    } else {
      tips.add('Your ${_where(h)} is often $n¢ $dir. ${_exercise(h, run.scale, library)}');
    }
  }
  if (tips.length < config.maxTips && run.missed >= config.missedTipMin) {
    tips.add('${run.missed} notes were not heard. Play slower, with one clear bow per note.');
  }
  if (tips.isEmpty) tips.add('No habitual error yet. Play it again with the drone to keep it that way.');
  return tips;
}

List<_Habit> _habits(List<(String, StoredNote)> history, GradingConfig grading, CoachingConfig config) {
  final groups = <String, List<StoredNote>>{};
  for (final (_, n) in history) {
    if (n.cents == null) continue;
    groups.putIfAbsent('${n.string}|${n.finger}|${n.placement ?? ''}', () => []).add(n);
  }
  final out = <_Habit>[];
  for (final g in groups.values) {
    if (g.length < config.minNotes) continue;
    final mean = g.map((n) => n.cents!).reduce((a, b) => a + b) / g.length;
    if (mean.abs() < config.sharpCents) continue;
    final same = g.where((n) => mean > 0 ? n.cents! > grading.greenCents : n.cents! < -grading.greenCents).length;
    final share = same / g.length;
    if (share < config.oftenFraction) continue;
    out.add(_Habit(g.first.string, g.first.finger, g.first.placement, mean, share));
  }
  out.sort((a, b) {
    final s = b.share.compareTo(a.share);
    if (s != 0) return s;
    final m = b.mean.abs().compareTo(a.mean.abs());
    if (m != 0) return m;
    final o = (_stringOrder[a.string] ?? 9).compareTo(_stringOrder[b.string] ?? 9);
    return o != 0 ? o : a.finger.compareTo(b.finger);
  });
  return out;
}

/// "3rd finger on A", "high 3rd finger on A", "open D string".
String _where(_Habit h) {
  if (h.finger == 0) return 'open ${h.string} string';
  return '${h.placement == null ? '' : '${h.placement} '}${ordinal(h.finger)} finger on ${h.string}';
}

bool _uses(ScaleDef s, _Habit h) => s.notes.any((n) => n.string == h.string && n.finger == h.finger && n.placement == h.placement);

/// The run's own scale if it uses that finger; else the bundled scale with the most notes on it, ties to the shorter, then library order.
String _exercise(_Habit h, ScaleDef played, ScaleLibrary library) {
  if (_uses(played, h)) return 'Play ${played.title} again slowly with the drone.';
  ScaleDef? best;
  var bestCount = 0;
  for (final s in library.scales) {
    final c = s.notes.where((n) => n.string == h.string && n.finger == h.finger && n.placement == h.placement).length;
    if (c > bestCount || (c == bestCount && c > 0 && best != null && s.notes.length < best.notes.length)) {
      best = s;
      bestCount = c;
    }
  }
  return best == null ? 'Play it slowly with the drone.' : 'Play ${best.title} slowly with the drone.';
}
