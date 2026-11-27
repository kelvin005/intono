import 'dart:math' as math;

import '../scales/grader.dart';
import '../scales/grading_config.dart';
import '../scales/scale.dart';

// Pure computations behind the practice database (ADR 0015): what one run stores, the caches derived from it, re-grading, and the
// cross-session statistics per finger. No database here, so these are tested directly.

/// One stored graded note (a row of `graded_notes`).
class StoredNote {
  const StoredNote({
    required this.idx,
    required this.midiNote,
    required this.string,
    required this.finger,
    required this.placement,
    required this.grade,
    this.cents,
    this.tStart,
    this.tEnd,
  });

  final int idx;
  final int midiNote;
  final String string;
  final int finger;
  final String? placement;
  final Grade grade;
  final double? cents;
  final double? tStart;
  final double? tEnd;

  StoredNote copyWith({String? string, int? finger, String? placement, bool clearPlacement = false, Grade? grade}) => StoredNote(
        idx: idx,
        midiNote: midiNote,
        string: string ?? this.string,
        finger: finger ?? this.finger,
        placement: clearPlacement ? null : (placement ?? this.placement),
        grade: grade ?? this.grade,
        cents: cents,
        tStart: tStart,
        tEnd: tEnd,
      );
}

/// The rows of one graded run, in scale order.
List<StoredNote> storedNotesOf(ScaleResult r) => [
      for (final g in r.notes)
        StoredNote(
          idx: g.index,
          midiNote: g.expected.midi,
          string: g.expected.string,
          finger: g.expected.finger,
          placement: g.expected.placement,
          grade: g.grade,
          cents: g.played == null ? null : g.cents,
          tStart: g.played?.tStart,
          tEnd: g.played?.tEnd,
        )
    ];

/// The session totals (a cache of the graded notes).
class Totals {
  const Totals(this.green, this.yellow, this.red, this.missed, this.noteCount);
  final int green, yellow, red, missed, noteCount;

  /// (🟢 + 0.5 × 🟡) / notes × 100, as the grader computes it.
  double get scorePercent => noteCount == 0 ? 0 : 100.0 * (green + 0.5 * yellow) / noteCount;
}

Totals totalsOf(List<StoredNote> notes) {
  var g = 0, y = 0, r = 0, m = 0;
  for (final n in notes) {
    switch (n.grade) {
      case Grade.green:
        g++;
      case Grade.yellow:
        y++;
      case Grade.red:
        r++;
      case Grade.missed:
        m++;
    }
  }
  return Totals(g, y, r, m, notes.length);
}

/// One row of `note_stats`. [placement] is '' for none.
class NoteStat {
  const NoteStat({
    required this.midiNote,
    required this.string,
    required this.finger,
    required this.placement,
    required this.count,
    required this.green,
    required this.yellow,
    required this.red,
    required this.missed,
    required this.meanCents,
    required this.meanAbsCents,
    required this.stdCents,
    required this.totalMs,
  });

  final int midiNote;
  final String string;
  final int finger;
  final String placement;
  final int count, green, yellow, red, missed;
  final double? meanCents, meanAbsCents, stdCents;
  final double totalMs;
}

/// The `note_stats` cache of one run: one row per (note, string, finger, placement), in first-appearance order. The cents statistics use
/// the played notes only (population standard deviation); missed notes are counted, carry no cents and add no time.
List<NoteStat> noteStatsOf(List<StoredNote> notes) {
  final groups = <String, List<StoredNote>>{};
  for (final n in notes) {
    groups.putIfAbsent('${n.midiNote}|${n.string}|${n.finger}|${n.placement ?? ''}', () => []).add(n);
  }
  return [
    for (final g in groups.values) _stat(g),
  ];
}

NoteStat _stat(List<StoredNote> g) {
  final t = totalsOf(g);
  final played = [for (final n in g) if (n.cents != null) n];
  double? mean, meanAbs, std;
  var ms = 0.0;
  if (played.isNotEmpty) {
    mean = played.map((n) => n.cents!).reduce((a, b) => a + b) / played.length;
    meanAbs = played.map((n) => n.cents!.abs()).reduce((a, b) => a + b) / played.length;
    final m = mean;
    std = math.sqrt(played.map((n) => (n.cents! - m) * (n.cents! - m)).reduce((a, b) => a + b) / played.length);
    for (final n in played) {
      if (n.tStart != null && n.tEnd != null) ms += (n.tEnd! - n.tStart!) * 1000;
    }
  }
  final f = g.first;
  return NoteStat(
    midiNote: f.midiNote,
    string: f.string,
    finger: f.finger,
    placement: f.placement ?? '',
    count: t.noteCount,
    green: t.green,
    yellow: t.yellow,
    red: t.red,
    missed: t.missed,
    meanCents: mean,
    meanAbsCents: meanAbs,
    stdCents: std,
    totalMs: ms,
  );
}

/// The grade of stored cents under [cfg], as the grader grades (|cents| ≤ green: 🟢, ≤ yellow: 🟡, else 🔴).
Grade gradeOfCents(double cents, GradingConfig cfg) {
  final a = cents.abs();
  if (a <= cfg.greenCents) return Grade.green;
  if (a <= cfg.yellowCents) return Grade.yellow;
  return Grade.red;
}

/// Re-grades and re-maps stored notes (ADR 0015 decision 4): a played note gets the grade its stored cents earn under [cfg]; a missed
/// note stays missed; string, finger and placement come from [scale]'s current data where the note at that position is still the same
/// MIDI note (otherwise the stored mapping stands). [scale] may be null (a scale no longer shipped): only the grades change.
List<StoredNote> regrade(List<StoredNote> notes, GradingConfig cfg, ScaleDef? scale) =>
    [for (final n in notes) _regradeOne(n, cfg, scale)];

StoredNote _regradeOne(StoredNote n, GradingConfig cfg, ScaleDef? scale) {
  var out = n.grade == Grade.missed || n.cents == null ? n : n.copyWith(grade: gradeOfCents(n.cents!, cfg));
  final exp = scale != null && n.idx >= 0 && n.idx < scale.notes.length ? scale.notes[n.idx] : null;
  if (exp != null && exp.midi == n.midiNote) {
    out = out.copyWith(string: exp.string, finger: exp.finger, placement: exp.placement, clearPlacement: exp.placement == null);
  }
  return out;
}

/// Statistics for one (string, finger, placement) across sessions: what the finger-level heatmap shows. [placement] is '' for none.
class FingerStat {
  const FingerStat({
    required this.string,
    required this.finger,
    required this.placement,
    required this.count,
    required this.green,
    required this.yellow,
    required this.red,
    required this.missed,
    required this.meanCents,
    required this.meanAbsCents,
    required this.stdCents,
  });

  final String string;
  final int finger;
  final String placement;
  final int count, green, yellow, red, missed;
  final double? meanCents, meanAbsCents, stdCents;

  int get played => count - missed;
}

/// Combines per-run rows into one row per (string, finger, placement), weighting the cents statistics by the number of played notes
/// (the pooled population standard deviation: E[x²] − mean²). Sorted by string (G, D, A, E), finger, placement.
List<FingerStat> combineFingerStats(Iterable<NoteStat> rows) {
  final acc = <String, _Acc>{};
  for (final r in rows) {
    acc.putIfAbsent('${r.string}|${r.finger}|${r.placement}', () => _Acc(r.string, r.finger, r.placement)).add(r);
  }
  const order = {'G': 0, 'D': 1, 'A': 2, 'E': 3};
  final out = [for (final a in acc.values) a.stat()];
  out.sort((a, b) {
    final s = (order[a.string] ?? 9).compareTo(order[b.string] ?? 9);
    if (s != 0) return s;
    final f = a.finger.compareTo(b.finger);
    return f != 0 ? f : a.placement.compareTo(b.placement);
  });
  return out;
}

class _Acc {
  _Acc(this.string, this.finger, this.placement);
  final String string;
  final int finger;
  final String placement;
  int count = 0, green = 0, yellow = 0, red = 0, missed = 0, played = 0;
  double sum = 0, sumAbs = 0, sumSq = 0;

  void add(NoteStat r) {
    count += r.count;
    green += r.green;
    yellow += r.yellow;
    red += r.red;
    missed += r.missed;
    final p = r.count - r.missed;
    if (p > 0 && r.meanCents != null) {
      played += p;
      sum += r.meanCents! * p;
      sumAbs += (r.meanAbsCents ?? r.meanCents!.abs()) * p;
      final sd = r.stdCents ?? 0;
      sumSq += (sd * sd + r.meanCents! * r.meanCents!) * p;
    }
  }

  FingerStat stat() {
    double? mean, meanAbs, std;
    if (played > 0) {
      mean = sum / played;
      meanAbs = sumAbs / played;
      final v = sumSq / played - mean * mean;
      std = math.sqrt(v < 0 ? 0 : v);
    }
    return FingerStat(
      string: string,
      finger: finger,
      placement: placement,
      count: count,
      green: green,
      yellow: yellow,
      red: red,
      missed: missed,
      meanCents: mean,
      meanAbsCents: meanAbs,
      stdCents: std,
    );
  }
}

/// A UUIDv7 (RFC 9562): 48 bits of Unix milliseconds, version 7, the variant bits, and 74 random bits.
String uuidV7(DateTime now, math.Random random) {
  final ms = now.toUtc().millisecondsSinceEpoch;
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  for (var i = 0; i < 6; i++) {
    b[i] = (ms >> (8 * (5 - i))) & 0xff;
  }
  b[6] = 0x70 | (b[6] & 0x0f);
  b[8] = 0x80 | (b[8] & 0x3f);
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
