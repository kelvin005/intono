import '../engine_api.dart';
import '../meter_state.dart' show noteName;
import 'grading_config.dart';
import 'scale.dart';

/// The grade of one expected note (ADR 0011 item 2).
enum Grade { green, yellow, red, missed }

class GradedNote {
  const GradedNote({required this.index, required this.expected, required this.grade, this.played, this.cents, this.wrong});

  /// Position in the scale (0 = the first note).
  final int index;
  final ScaleNote expected;
  final Grade grade;

  /// The played note aligned to it (after merging splits); null if missed.
  final Note? played;

  /// Cents from the expected note's target in the engine's tuning; null if missed or wrong.
  final double? cents;

  /// A wrong note: a note was played in this note's place but is further than the label window from it. The expected note is then
  /// graded [Grade.missed] and [played] and [cents] are null; this is what was played instead (never graded, never given cents).
  final Note? wrong;

  bool get isWrong => wrong != null;

  /// The note that was heard in this note's place, right or wrong; null if nothing.
  Note? get heard => played ?? wrong;

  /// The pitch name of the wrong note, e.g. "E4" (its nearest semitone).
  String? get wrongName => wrong == null ? null : noteName((wrong!.midiNote + wrong!.meanCents / 100).round());
}

/// The nearest-semitone hint for a far-off note (ADR 0018 note): [midi] is the neighbour on the side the note is off, [closer] is true
/// when the note really is nearer to it than to the expected note (more than 50 cents), false for "almost" (between the threshold and 50).
class NeighbourHint {
  const NeighbourHint(this.midi, this.closer, this.sharp);
  final int midi;
  final bool closer;
  final bool sharp;

  /// Pitch class only ("B", "C#"): the neighbour is the adjacent semitone, so the octave adds nothing.
  String get name => noteName(midi).replaceAll(RegExp(r'-?\d+$'), '');
}

/// A hint for [g] if it is a played note more than [GradingConfig.neighbourCents] from the expected note; null otherwise.
NeighbourHint? neighbourHint(GradedNote g, GradingConfig cfg) {
  final c = g.cents;
  if (c == null || c.abs() <= cfg.neighbourCents) return null;
  return NeighbourHint(g.expected.midi + (c > 0 ? 1 : -1), c.abs() > 50, c > 0);
}

enum SuggestionKind { octave, scale }

/// "You seem to be playing an octave higher. Switch?" / "This sounds like D major, 1 octave. Switch?": the run, regraded against
/// [scale], matches clearly better than against the chosen scale.
class ScaleSuggestion {
  const ScaleSuggestion(this.kind, this.scale, {this.semitones = 0});

  final SuggestionKind kind;

  /// What to regrade against: the chosen scale moved by [semitones] (±12), or another scale of the library.
  final ScaleDef scale;

  /// +12: the player is an octave higher than the scale; -12: an octave lower; 0 for [SuggestionKind.scale].
  final int semitones;

  String get message => kind == SuggestionKind.octave
      ? 'You seem to be playing an octave ${semitones > 0 ? 'higher' : 'lower'}. Switch?'
      : 'This sounds like ${scale.title}. Switch?';
}

/// Whether a run that fits the chosen scale badly fits another octave of it (exactly ±12 semitones), or another scale of [library],
/// much better. Needs at least [minNotes] played notes. The octave is tried first. Null when there is no confident suggestion.
ScaleSuggestion? suggestScale(ScaleDef current, List<Note> played, ScaleLibrary library, GradingConfig cfg, {int minNotes = 4}) {
  final used = _usable(played, cfg);
  if (used.length < minNotes) return null;
  double share(ScaleDef s) => gradeScale(s, played, cfg).notes.where((g) => g.played != null).length / used.length;
  final base = share(current);
  ScaleSuggestion? best;
  var bestShare = 0.0;
  void consider(ScaleSuggestion c) {
    final sh = share(c.scale);
    if (sh >= cfg.suggestMatchFraction && sh - base >= cfg.suggestMinGain && sh > bestShare + 1e-9) {
      best = c;
      bestShare = sh;
    }
  }

  for (final d in const [12, -12]) {
    consider(ScaleSuggestion(SuggestionKind.octave, current.shifted(d), semitones: d));
  }
  if (best != null) return best;
  for (final s in library.scales) {
    if (s.id != current.id) consider(ScaleSuggestion(SuggestionKind.scale, s));
  }
  return best;
}

/// The played notes that count: split notes merged, notes shorter than the minimum dropped.
List<Note> _usable(List<Note> played, GradingConfig cfg) {
  final ordered = [...played]..sort((a, b) => a.tStart.compareTo(b.tStart));
  final merged = _mergeSplits(ordered, cfg.mergeGapMs / 1000, cfg.mergeMaxCentsDiff);
  return [for (final n in merged) if ((n.tEnd - n.tStart) * 1000 >= cfg.minNoteMs) n];
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
    this.wrong = 0,
    this.heard = 0,
    this.notHeard = false,
    this.badRun = false,
  });

  final ScaleDef scale;

  /// One entry per expected note, in scale order.
  final List<GradedNote> notes;

  /// Played notes not aligned to any expected note (stray, repeated, slipped).
  final List<Note> extras;
  final int green, yellow, red, missed;

  /// Wrong notes (counted in [missed] too: the expected note was not played), and how many notes were heard at all (played, wrong or
  /// stray: after merging splits and dropping notes shorter than the minimum).
  final int wrong, heard;

  /// Fewer than [GradingConfig.minHeardFraction] of the expected notes were heard: nothing is graded, shown as a grade, saved or coached.
  final bool notHeard;

  /// More than [GradingConfig.badRunFraction] of the expected notes were missed or wrong: shown, but saved only if the player says so.
  final bool badRun;

  /// (🟢 + 0.5 × 🟡) / expected notes × 100; missed notes count as 🔴 (Kelechi, 2026-11-27).
  final double scorePercent;
}

/// Cents from [n] to the target of [expectedMidi]: the engine reports cents from the target of its own nearest note; the step to the
/// expected note is counted in semitones (exact in equal temperament; just and Pythagorean need per-degree offsets, not in v1).
double centsToExpected(Note n, int expectedMidi) => (n.midiNote - expectedMidi) * 100.0 + n.meanCents;

/// Grades a played scale against its definition: merge same-pitch splits, drop notes shorter than [GradingConfig.minNoteMs], align
/// with a semi-global edit distance (a match within the label window, 60 cents, costs 0; a wrong note, a missed note and an extra note cost 1 each; the
/// unplayed rest of the scale is free), then grade. Works on a finished run and on a run still being played.
ScaleResult gradeScale(ScaleDef scale, List<Note> played, GradingConfig cfg) {
  final notes = _usable(played, cfg);
  final exp = scale.notes;
  final n = exp.length, m = notes.length;

  // Substitution cost: a match within 50 cents is free; a wrong note costs 1, the same as a missed or an extra note. A tiny distance term
  // makes ties prefer the closer note, and a wrong note within 3 semitones (a plausible slip, e.g. F for F#) costs a hair under 1 so it
  // takes the next slot rather than counting as an extra when the two tie at the end of a run in progress; a farther stray note (or a
  // speech blip) stays an extra there. In the middle of a run nothing changes: a wrong note (about 1) always beats extra + missed (2).
  double sub(int i, int j) {
    final d = centsToExpected(notes[j], exp[i].midi).abs();
    if (d <= cfg.labelWindowCents) return d / 1e6;
    if (d <= 300) return 1 - 1e-3 + d / 1e6;
    return 1 + d / 1e6;
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

  // Semi-global: the part of the scale after the last played note costs nothing (it is not played yet, or the run was stopped), so the
  // alignment ends at the cheapest row of the last column (ties: the later row, more of the scale covered); those trailing notes are
  // still graded missed. Without this, a run in progress could "save" missed notes by jumping into the descending half (a stray G#5
  // after A3 became a wrong G4 and the next B3 the descending B3), and the opening G3 tied with the closing G3 (both found with the
  // scale screen). On a tie in the trace, an expected note is missed before a played note is matched to it, so matches sit early.
  var iEnd = 0;
  for (var r = 0; r <= n; r++) {
    if (cost[r][m] <= cost[iEnd][m] + 1e-12) iEnd = r;
  }
  final matchOf = List<int?>.filled(n, null);
  final extra = <int>[];
  var i = iEnd, j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && (cost[i][j] - (cost[i - 1][j] + 1)).abs() < 1e-12) {
      i--;
    } else if (i > 0 && j > 0 && (cost[i][j] - (cost[i - 1][j - 1] + sub(i - 1, j - 1))).abs() < 1e-12) {
      matchOf[i - 1] = j - 1;
      i--;
      j--;
    } else {
      extra.add(j - 1);
      j--;
    }
  }

  var green = 0, yellow = 0, red = 0, missed = 0, wrong = 0;
  final graded = <GradedNote>[];
  for (var k = 0; k < n; k++) {
    final mj = matchOf[k];
    if (mj == null) {
      missed++;
      graded.add(GradedNote(index: k, expected: exp[k], grade: Grade.missed));
      continue;
    }
    final c = centsToExpected(notes[mj], exp[k].midi);
    if (c.abs() > cfg.labelWindowCents) {
      // a wrong note: never graded as the expected note and never given cents (a +1029¢ reading is a different note, not an error)
      missed++;
      wrong++;
      graded.add(GradedNote(index: k, expected: exp[k], grade: Grade.missed, wrong: notes[mj]));
      continue;
    }
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
  // heard: the played notes that count (merged, long enough): wrong or stray ones too, since something was played; silence is not
  final heard = notes.length;
  final notHeard = n > 0 && heard < cfg.minHeardFraction * n;
  return ScaleResult(
    scale: scale,
    notes: graded,
    extras: [for (final e in extra.reversed) notes[e]],
    green: green,
    yellow: yellow,
    red: red,
    missed: missed,
    scorePercent: score,
    wrong: wrong,
    heard: heard,
    notHeard: notHeard,
    badRun: !notHeard && n > 0 && missed > cfg.badRunFraction * n,
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
