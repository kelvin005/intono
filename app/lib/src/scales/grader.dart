import '../engine_api.dart';
import 'grading_config.dart';
import 'scale.dart';

/// The grade of one expected note (ADR 0011 item 2).
enum Grade { green, yellow, red, missed }

class GradedNote {
  const GradedNote({required this.index, required this.expected, required this.grade, this.played, this.cents});

  /// Position in the scale (0 = the first note).
  final int index;
  final ScaleNote expected;
  final Grade grade;

  /// The played note aligned to it (after merging splits); null if missed.
  final Note? played;

  /// Cents from the expected note's target in the engine's tuning; null if missed.
  final double? cents;
}

class ScaleResult {
  const ScaleResult({
    required this.scale,
    required this.notes,
    required this.extras,
    required this.green,
    required this.yellow,
    required this.red,
    required this.missed,
    required this.scorePercent,
  });

  final ScaleDef scale;

  /// One entry per expected note, in scale order.
  final List<GradedNote> notes;

  /// Played notes not aligned to any expected note (stray, repeated, slipped).
  final List<Note> extras;
  final int green, yellow, red, missed;

  /// (🟢 + 0.5 × 🟡) / expected notes × 100; missed notes count as 🔴 (Kelechi, 2026-11-27).
  final double scorePercent;
}

/// Cents from [n] to the target of [expectedMidi]: the engine reports cents from the target of its own nearest note; the step to the
/// expected note is counted in semitones (exact in equal temperament; just and Pythagorean need per-degree offsets, not in v1).
double centsToExpected(Note n, int expectedMidi) => (n.midiNote - expectedMidi) * 100.0 + n.meanCents;

/// Grades a played scale against its definition: merge same-pitch splits, drop notes shorter than [GradingConfig.minNoteMs], align
/// with an edit distance (a match within 50 cents costs 0, a wrong note, a missed note and an extra note cost 1 each), then grade.
ScaleResult gradeScale(ScaleDef scale, List<Note> played, GradingConfig cfg) {
  final ordered = [...played]..sort((a, b) => a.tStart.compareTo(b.tStart));
  final merged = _mergeSplits(ordered, cfg.mergeGapMs / 1000, cfg.mergeMaxCentsDiff);
  final notes = [for (final n in merged) if ((n.tEnd - n.tStart) * 1000 >= cfg.minNoteMs) n];
  final exp = scale.notes;
  final n = exp.length, m = notes.length;

  // Edit distance with a tiny pitch-distance term so ties prefer the closer note.
  double sub(int i, int j) {
    final d = centsToExpected(notes[j], exp[i].midi).abs();
    return (d <= 50 ? 0.0 : 1.0) + d / 1e6;
  }

  final cost = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
  for (var i = 1; i <= n; i++) {
    cost[i][0] = i.toDouble();
  }
  for (var j = 1; j <= m; j++) {
    cost[0][j] = j.toDouble();
  }
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      final a = cost[i - 1][j - 1] + sub(i - 1, j - 1);
      final b = cost[i - 1][j] + 1; // expected i-1 missed
      final c = cost[i][j - 1] + 1; // played j-1 extra
      cost[i][j] = a <= b && a <= c ? a : (b <= c ? b : c);
    }
  }

  // Trace back.
  final matchOf = List<int?>.filled(n, null);
  final extra = <int>[];
  var i = n, j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && (cost[i][j] - (cost[i - 1][j - 1] + sub(i - 1, j - 1))).abs() < 1e-12) {
      matchOf[i - 1] = j - 1;
      i--;
      j--;
    } else if (i > 0 && (cost[i][j] - (cost[i - 1][j] + 1)).abs() < 1e-12) {
      i--;
    } else {
      extra.add(j - 1);
      j--;
    }
  }

  var green = 0, yellow = 0, red = 0, missed = 0;
  final graded = <GradedNote>[];
  for (var k = 0; k < n; k++) {
    final mj = matchOf[k];
    if (mj == null) {
      missed++;
      graded.add(GradedNote(index: k, expected: exp[k], grade: Grade.missed));
      continue;
    }
    final c = centsToExpected(notes[mj], exp[k].midi);
    final g = c.abs() <= cfg.greenCents
        ? Grade.green
        : c.abs() <= cfg.yellowCents
            ? Grade.yellow
            : Grade.red;
    switch (g) {
      case Grade.green:
        green++;
      case Grade.yellow:
        yellow++;
      default:
        red++;
    }
    graded.add(GradedNote(index: k, expected: exp[k], grade: g, played: notes[mj], cents: c));
  }
  final score = n == 0 ? 0.0 : 100.0 * (green + 0.5 * yellow) / n;
  return ScaleResult(
    scale: scale,
    notes: graded,
    extras: [for (final e in extra.reversed) notes[e]],
    green: green,
    yellow: yellow,
    red: red,
    missed: missed,
    scorePercent: score,
  );
}

/// Consecutive notes of the same MIDI number, a gap up to [gapS] and mean pitches within [maxCentsDiff] of each other are one note
/// split in two: times from the first start to the last end, cents and confidence weighted by frame count (ADR 0004: same-pitch splits
/// are merged by the grader). The pitch condition keeps a very sharp or flat note that the engine named after its neighbour (an F#4
/// 60 cents sharp reads as G4 -40) from being merged into a following G4.
List<Note> _mergeSplits(List<Note> notes, double gapS, double maxCentsDiff) {
  final out = <Note>[];
  for (final n in notes) {
    if (out.isNotEmpty &&
        out.last.midiNote == n.midiNote &&
        n.tStart - out.last.tEnd <= gapS &&
        (n.meanCents - out.last.meanCents).abs() <= maxCentsDiff) {
      final p = out.removeLast();
      final f = p.frameCount + n.frameCount;
      double w(double a, double b) => f == 0 ? (a + b) / 2 : (a * p.frameCount + b * n.frameCount) / f;
      out.add(Note(
        tStart: p.tStart,
        tEnd: n.tEnd > p.tEnd ? n.tEnd : p.tEnd,
        midiNote: p.midiNote,
        meanCents: w(p.meanCents, n.meanCents),
        stdCents: w(p.stdCents, n.stdCents),
        vibratoRateHz: w(p.vibratoRateHz, n.vibratoRateHz),
        vibratoWidthCents: w(p.vibratoWidthCents, n.vibratoWidthCents),
        meanConfidence: w(p.meanConfidence, n.meanConfidence),
        frameCount: f,
      ));
    } else {
      out.add(n);
    }
  }
  return out;
}
