import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/coaching/coaching.dart';
import 'package:intono_app/src/db/practice_stats.dart';
import 'package:intono_app/src/engine_api.dart';
import 'package:intono_app/src/scales/grader.dart';
import 'package:intono_app/src/scales/grading_config.dart';
import 'package:intono_app/src/scales/scale.dart';

// Coaching tips in words (ADR 0016): rule-based templates. Written before the rules.

final lib = ScaleLibrary.fromJsonString(File('assets/scales/beginner.json').readAsStringSync());
final gMajor = lib.byId('g_major_1oct')!; // G and D strings only
const grading = GradingConfig();
const cfg = CoachingConfig();

StoredNote sn(int idx, String string, int finger, String? placement, double? cents) => StoredNote(
    idx: idx,
    midiNote: 60,
    string: string,
    finger: finger,
    placement: placement,
    grade: cents == null ? Grade.missed : gradeOfCents(cents, grading),
    cents: cents,
    tStart: cents == null ? null : 0.5 * idx,
    tEnd: cents == null ? null : 0.5 * idx + 0.4);

List<(String, StoredNote)> cell(String string, int finger, String? placement, List<double?> cents) =>
    [for (var i = 0; i < cents.length; i++) ('s${i % 3}', sn(i, string, finger, placement, cents[i]))];

/// A G major run, every note played in tune unless [missedAt] says otherwise.
ScaleResult run({Set<int> missedAt = const {}}) {
  final notes = <Note>[];
  for (var i = 0; i < gMajor.notes.length; i++) {
    if (missedAt.contains(i)) continue;
    notes.add(Note(
        tStart: 0.5 * i,
        tEnd: 0.5 * i + 0.4,
        midiNote: gMajor.notes[i].midi,
        meanCents: 0,
        stdCents: 2,
        vibratoRateHz: 0,
        vibratoWidthCents: 0,
        meanConfidence: 0.99,
        frameCount: 75));
  }
  return gradeScale(gMajor, notes, grading);
}

List<String> tips(List<(String, StoredNote)> history, ScaleResult r, {CoachingConfig c = cfg}) =>
    coachingTips(history: history, run: r, library: lib, grading: grading, config: c);

void main() {
  test('a consistent error gets the habit tip with an exercise from the library', () {
    final t = tips(cell('A', 3, null, [14, 16, 15, 13, 17]), run());
    expect(t.first, 'Your 3rd finger on A is often 15¢ sharp. Play F major, 1 octave slowly with the drone.');
  });

  test('the placement is named, and the exercise is the scale with the most notes on that finger', () {
    final t = tips(cell('A', 3, 'high', [-14, -16, -15, -13, -17]), run());
    expect(t.first, 'Your high 3rd finger on A is often 15¢ flat. Play E harmonic minor, 1 octave slowly with the drone.');
  });

  test('if the run just played uses that finger, the exercise is to play it again', () {
    final t = tips(cell('D', 2, 'high', [12, 12, 12, 12]), run());
    expect(t.first, 'Your high 2nd finger on D is often 12¢ sharp. Play G major, 1 octave again slowly with the drone.');
  });

  test('an open string is a tuning matter', () {
    final t = tips(cell('D', 0, null, [-10, -11, -9, -10, -12]), run());
    expect(t.first, 'Your open D string is often 10¢ flat. Tune it against the drone before you play.');
  });

  test('errors that point both ways are not a habit, even with a large spread', () {
    final t = tips(cell('A', 1, null, [20, -20, 18, -18, 22, -22]), run());
    expect(t.single, startsWith('No habitual error yet'));
  });

  test('the average must reach sharp_cents', () {
    expect(tips(cell('A', 1, null, [9, 9, 9, 9, 9]), run()).single, startsWith('No habitual error'));
    expect(tips(cell('A', 1, null, [10, 10, 10, 10, 10]), run()).first, startsWith('Your 1st finger on A is often 10¢ sharp'));
  });

  test('fewer than min_notes played notes is not enough evidence; missed notes do not count', () {
    expect(tips(cell('A', 1, null, [15, 15, 15]), run()).single, startsWith('No habitual error'));
    expect(tips(cell('A', 1, null, [15, 15, 15, null, null]), run()).single, startsWith('No habitual error'));
    expect(tips(cell('A', 1, null, [15, 15, 15, 15]), run()).first, startsWith('Your 1st finger on A'));
  });

  test('often_fraction: 3 of 5 off the same way passes at 0.6, 2 of 5 does not', () {
    expect(tips(cell('E', 1, 'low', [-20, -20, -20, 0, 0]), run()).first, startsWith('Your low 1st finger on E is often 12¢ flat'));
    expect(tips(cell('E', 1, 'low', [-30, -30, 0, 0, 0]), run()).single, startsWith('No habitual error'));
  });

  test('the most consistent error comes first; the second gets "too" and no exercise', () {
    final h = [
      ...cell('A', 3, null, [25, 25, 25, 0, 0]), // 3/5 sharp, average 15
      ...cell('E', 1, 'low', [-12, -12, -12, -12, -12]), // 5/5 flat, average 12
    ];
    final t = tips(h, run());
    expect(t, [
      'Your low 1st finger on E is often 12¢ flat. Play A natural minor, 2 octaves slowly with the drone.',
      'Your 3rd finger on A is often 15¢ sharp too.',
    ]);
  });

  test('missed notes get their own tip after the habit tips, within max_tips', () {
    expect(tips(const [], run(missedAt: {3, 4, 5})), ['3 notes were not heard. Play slower, with one clear bow per note.']);
    expect(tips(const [], run(missedAt: {3})).single, startsWith('No habitual error'), reason: 'one missed note is below missed_tip_min');
    final t = tips(cell('A', 3, null, [15, 15, 15, 15]), run(missedAt: {3, 4}));
    expect(t.length, 2);
    expect(t.last, '2 notes were not heard. Play slower, with one clear bow per note.');
    final three = tips([...cell('A', 3, null, [15, 15, 15, 15]), ...cell('E', 1, 'low', [-15, -15, -15, -15])], run(missedAt: {3, 4}));
    expect(three.length, 2, reason: 'max_tips');
    expect(three.last, endsWith('too.'));
  });

  test('nothing to fix', () {
    expect(tips(cell('A', 1, null, [1, -2, 0, 3]), run()), ['No habitual error yet. Play it again with the drone to keep it that way.']);
  });

  group('config', () {
    test('the bundled file parses to the ADR 0016 values', () {
      final c = CoachingConfig.fromJsonString(File('assets/config/coaching.json').readAsStringSync());
      expect([c.minNotes, c.sharpCents, c.oftenFraction, c.missedTipMin, c.maxTips], [4, 10, 0.6, 2, 2]);
    });

    test('an unknown format or inconsistent values are rejected', () {
      expect(() => CoachingConfig.fromJsonString('{"format": 2}'), throwsFormatException);
      expect(() => CoachingConfig.fromJsonString('{"format": 1, "often_fraction": 1.5}'), throwsFormatException);
      expect(() => CoachingConfig.fromJsonString('{"format": 1, "max_tips": 0}'), throwsFormatException);
      expect(() => CoachingConfig.fromJsonString('{"format": 1, "min_notes": 0}'), throwsFormatException);
    });
  });

  group('far-off notes (ADR 0018 note)', () {
    ScaleResult runWith(Map<int, double> cents) {
      final notes = <Note>[
        for (var i = 0; i < gMajor.notes.length; i++)
          Note(
              tStart: 0.5 * i,
              tEnd: 0.5 * i + 0.4,
              midiNote: gMajor.notes[i].midi,
              meanCents: cents[i] ?? 0,
              stdCents: 2,
              vibratoRateHz: 0,
              vibratoWidthCents: 0,
              meanConfidence: 0.99,
              frameCount: 75)
      ];
      return gradeScale(gMajor, notes, grading);
    }

    test('a note far flat gets "very flat, almost a <neighbour>", before the habit tips', () {
      final t = tips(cell('A', 3, null, [14, 16, 15, 13, 17]), runWith({3: -55})); // index 3 is C4 in G major
      expect(t.first, 'Your C4 was very flat, almost a B.');
      expect(t.length, 2);
      expect(t[1], startsWith('Your 3rd finger on A is often 15¢ sharp.'));
    });

    test('a note far sharp says very sharp; the worst note is named and the others counted', () {
      final t = tips([], runWith({1: 44, 4: 58, 6: -47}));
      expect(t.first, 'Your D4 was very sharp, almost a D#. 2 more were as far off.');
    });

    test('notes within the threshold add nothing', () {
      expect(tips([], runWith({3: -35, 4: 30})).single, startsWith('No habitual error yet'));
    });

    test('one far note and nothing else is the only tip; max_tips still holds', () {
      expect(tips([], runWith({3: -55}), c: const CoachingConfig(maxTips: 1)), ['Your C4 was very flat, almost a B.']);
    });
  });

  group('only trustworthy notes feed the tips (Kelechi phone test, 2026-11-28)', () {
    test('notes beyond the label window never make a habit, however many there are', () {
      final history = cell('D', 0, null, [1029, 511, 287, 262, 119, 264, 507]); // stored before wrong notes existed
      final tips = coachingTips(history: history, run: run(), library: lib, grading: grading, config: cfg);
      expect(tips.where((t) => t.contains('often')), isEmpty);
    });

    test('a wrong note is not "not heard": the missed-notes tip counts only the really missed ones', () {
      final played = [for (var i = 0; i < 4; i++) Note(tStart: i * 0.6, tEnd: i * 0.6 + 0.4, midiNote: gMajor.notes[i].midi, meanCents: 0, stdCents: 2, vibratoRateHz: 0, vibratoWidthCents: 0, meanConfidence: 0.99, frameCount: 75)];
      final r = gradeScale(gMajor, [...played, Note(tStart: 2.4, tEnd: 2.8, midiNote: 73, meanCents: 0, stdCents: 2, vibratoRateHz: 0, vibratoWidthCents: 0, meanConfidence: 0.99, frameCount: 75)], grading);
      expect(r.wrong, 1);
      final tips = coachingTips(history: [for (final n in storedNotesOf(r)) ('s', n)], run: r, library: lib, grading: grading, config: cfg);
      expect(tips.any((t) => t.contains('10 notes were not heard')), isTrue); // 15 - 4 played - 1 wrong
    });
  });
}
