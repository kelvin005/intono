import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/engine_api.dart';
import 'package:intono_app/src/scales/grader.dart';
import 'package:intono_app/src/scales/grading_config.dart';
import 'package:intono_app/src/scales/scale.dart';

// The scale grader (ADR 0011 item 2), written before the implementation. Synthetic note sequences, the way intono_read_notes reports them.

final lib = ScaleLibrary.fromJsonString(File('assets/scales/beginner.json').readAsStringSync());
final gMajor = lib.byId('g_major_1oct')!; // G3 A3 B3 C4 D4 E4 F#4 G4 F#4 E4 D4 C4 B3 A3 G3
const cfg = GradingConfig(); // the v1 defaults: 5 / 15 cents, 80 ms, merge gap 120 ms within 25 cents

Note note(int midi, double cents, double t0, {double ms = 400, int? frames}) => Note(
      tStart: t0,
      tEnd: t0 + ms / 1000,
      midiNote: midi,
      meanCents: cents,
      stdCents: 2,
      vibratoRateHz: 0,
      vibratoWidthCents: 0,
      meanConfidence: 0.99,
      frameCount: frames ?? (ms / 5.333).round(),
    );

/// The scale played with the given cents per note (default 0), 0.5 s apart.
List<Note> play(ScaleDef s, {Map<int, double> cents = const {}}) =>
    [for (var i = 0; i < s.notes.length; i++) note(s.notes[i].midi, cents[i] ?? 0, i * 0.5)];

void main() {
  test('a scale played in tune: every note green, 100 %', () {
    final r = gradeScale(gMajor, play(gMajor), cfg);
    expect(r.notes.length, 15);
    expect(r.green, 15);
    expect(r.scorePercent, 100);
    expect(r.extras, isEmpty);
    expect(r.notes.every((g) => g.played != null && g.cents == 0), isTrue);
  });

  test('grade boundaries are inclusive: ±5 green, ±15 yellow, beyond red', () {
    final r = gradeScale(gMajor, play(gMajor, cents: {0: 5.0, 1: 5.1, 2: 15.0, 3: 15.1, 4: -5.0, 5: -15.0, 6: -15.1}), cfg);
    expect([for (final g in r.notes.take(7)) g.grade],
        [Grade.green, Grade.yellow, Grade.yellow, Grade.red, Grade.green, Grade.yellow, Grade.red]);
  });

  test('score = (green + 0.5 yellow) / expected, with the counts', () {
    final cents = <int, double>{for (var i = 10; i < 14; i++) i: 10.0, 14: 30.0}; // 10 green, 4 yellow, 1 red
    final r = gradeScale(gMajor, play(gMajor, cents: cents), cfg);
    expect((r.green, r.yellow, r.red, r.missed), (10, 4, 1, 0));
    expect(r.scorePercent, closeTo(80.0, 1e-9)); // (10 + 2) / 15
  });

  test('a missed note is missed and does not shift the later grades', () {
    final played = play(gMajor, cents: {5: 12.0})..removeAt(3); // C4 not played; E4 (index 5) yellow
    final r = gradeScale(gMajor, played, cfg);
    expect(r.notes[3].grade, Grade.missed);
    expect(r.notes[3].played, isNull);
    expect(r.notes[5].grade, Grade.yellow);
    expect((r.green, r.yellow, r.red, r.missed), (13, 1, 0, 1));
    expect(r.scorePercent, closeTo(100 * 13.5 / 15, 1e-9));
  });

  test('an extra note is reported as extra, the scale still aligns', () {
    final played = play(gMajor)..insert(5, note(73, 3, 2.25)); // a stray C#5 between D4 and E4
    final r = gradeScale(gMajor, played, cfg);
    expect(r.green, 15);
    expect(r.extras.map((n) => n.midiNote), [73]);
  });

  test('a wrong note takes its slot, graded red with its distance in cents', () {
    final played = play(gMajor);
    played[6] = note(65, 0, 3.0); // F natural instead of F#4
    final r = gradeScale(gMajor, played, cfg);
    expect(r.notes[6].grade, Grade.red);
    expect(r.notes[6].cents, closeTo(-100, 1e-9));
    expect(r.green, 14);
    expect(r.extras, isEmpty);
  });

  test('an octave error is a wrong note in its slot, not a shift', () {
    final played = play(gMajor);
    played[1] = note(69, 1, 0.5); // A4 reported for A3
    final r = gradeScale(gMajor, played, cfg);
    expect(r.notes[1].grade, Grade.red);
    expect(r.notes[1].cents, closeTo(1201, 1e-9));
    expect(r.green, 14);
  });

  test('a repeated note is one extra', () {
    // G4 (index 7) ends at 3.9 s; the same G4 again 200 ms later (a separate bow); everything after it moves 0.6 s.
    final base = play(gMajor);
    final played = [...base.take(8), note(67, 2, 4.1), for (final n in base.skip(8)) note(n.midiNote, n.meanCents, n.tStart + 0.6)];
    final r = gradeScale(gMajor, played, cfg);
    expect(r.green, 15);
    expect(r.extras.length, 1);
    expect(r.extras.single.midiNote, 67);
  });

  test('a very sharp note read as its upper neighbour is not merged into that neighbour', () {
    final played = play(gMajor);
    played[6] = note(67, -40, 3.0); // F#4 +60, named G4 -40 by the engine; the G4 that follows starts 100 ms after it ends
    final r = gradeScale(gMajor, played, cfg);
    expect(r.notes[6].played, isNotNull);
    expect(r.notes[7].grade, Grade.green);
    expect(r.extras, isEmpty);
  });

  test('a same-pitch split is merged first (frame-weighted cents), so it is neither extra nor too short', () {
    final played = play(gMajor);
    final b = played[2];
    played
      ..removeAt(2)
      ..insertAll(2, [note(59, 4, b.tStart, ms: 100, frames: 20), note(59, -2, b.tStart + 0.11, ms: 100, frames: 10)]);
    final r = gradeScale(gMajor, played, cfg);
    expect(r.extras, isEmpty);
    expect(r.notes[2].grade, Grade.green);
    expect(r.notes[2].cents, closeTo((4 * 20 + -2 * 10) / 30, 1e-9));
    expect(r.notes[2].played!.tEnd, closeTo(b.tStart + 0.21, 1e-9));
  });

  test('pieces of the same pitch further apart than the merge gap stay separate', () {
    // B3 (index 2) ends at 1.4 s; a second B3 starts 200 ms later; everything after it moves 0.6 s.
    final base = play(gMajor);
    final played = [
      ...base.take(3),
      note(59, 0, 1.6),
      for (final n in base.skip(3)) note(n.midiNote, n.meanCents, n.tStart + 0.6),
    ];
    final r = gradeScale(gMajor, played, cfg);
    expect(r.extras.length, 1);
    expect(r.extras.single.midiNote, 59);
    expect(r.green, 15);
  });

  test('notes shorter than min_note_ms (80) are not graded: a 60 ms glitch is ignored, a 70 ms scale note is missed', () {
    final base = play(gMajor);
    final glitchy = [...base]..insert(4, note(80, 0, 1.92, ms: 60)); // a 60 ms glitch between C4 and D4
    final r1 = gradeScale(gMajor, glitchy, cfg);
    expect(r1.extras, isEmpty);
    expect(r1.green, 15);
    final withShort = [...base]..[9] = note(base[9].midiNote, 0, base[9].tStart, ms: 70); // E4 descending, 70 ms
    final r2 = gradeScale(gMajor, withShort, cfg);
    expect(r2.notes[9].grade, Grade.missed);
    expect(r2.missed, 1);
    expect(r2.extras, isEmpty);
  });

  test('a fast scale in 120 ms semiquavers is graded, not missed (min_note_ms 80, Kelechi 2026-11-27)', () {
    final s = gMajor;
    final fast = [for (var i = 0; i < s.notes.length; i++) note(s.notes[i].midi, i == 4 ? 8 : 0, i * 0.125, ms: 120)];
    final r = gradeScale(s, fast, cfg);
    expect(r.missed, 0);
    expect(r.extras, isEmpty);
    expect((r.green, r.yellow), (14, 1));
    expect(r.notes.every((g) => g.played != null), isTrue);
  });

  test('cents to the expected note when the engine named the neighbour', () {
    final played = play(gMajor);
    played[6] = note(67, -40, 3.0); // engine: G4 -40, i.e. F#4 +60
    final r = gradeScale(gMajor, played, cfg);
    expect(r.notes[6].cents, closeTo(60, 1e-9));
    expect(r.notes[6].grade, Grade.red);
  });

  test('nothing played: every note missed, 0 %', () {
    final r = gradeScale(gMajor, const [], cfg);
    expect(r.missed, 15);
    expect(r.scorePercent, 0);
  });

  test('the thresholds come from the bundled config, and changing them changes the grades', () {
    final bundled = GradingConfig.fromJsonString(File('assets/config/grading.json').readAsStringSync());
    expect((bundled.greenCents, bundled.yellowCents, bundled.minNoteMs, bundled.mergeGapMs, bundled.mergeMaxCentsDiff), (5.0, 15.0, 80.0, 120.0, 25.0));
    final strict = const GradingConfig(greenCents: 3, yellowCents: 8);
    final r = gradeScale(gMajor, play(gMajor, cents: {0: 4, 1: 9}), strict);
    expect([r.notes[0].grade, r.notes[1].grade], [Grade.yellow, Grade.red]);
  });

  test('a two-octave scale with a few errors', () {
    final s = lib.byId('a_melodic_minor_2oct')!; // descending is natural: G and F naturals on the way down
    final played = play(s, cents: {3: -8, 20: 16})..removeAt(10);
    final r = gradeScale(s, played, cfg);
    expect(r.notes.length, 29);
    expect((r.green, r.yellow, r.red, r.missed), (26, 1, 1, 1));
  });

  test('a partial run aligns to the start of the scale (the tonic appears twice: opening and closing)', () {
    for (var k = 1; k < gMajor.notes.length; k++) {
      final r = gradeScale(gMajor, play(gMajor).sublist(0, k), cfg);
      expect([for (final g in r.notes) if (g.played != null) g.index], List.generate(k, (i) => i), reason: 'first $k notes');
    }
  });

  test('a run in progress does not jump ahead: a far stray note is an extra, a near wrong note takes the next slot', () {
    final base = play(gMajor).sublist(0, 2); // G3 A3
    final far = gradeScale(gMajor, [...base, note(80, 0, 0.8)], cfg); // G#5, nowhere near B3
    expect(far.extras.single.midiNote, 80);
    expect([for (final g in far.notes) if (g.played != null) g.index], [0, 1]);
    final farThenB = gradeScale(gMajor, [...base, note(80, 0, 0.8), note(59, 0, 1.2)], cfg);
    expect(farThenB.notes[2].grade, Grade.green, reason: 'B3 is the 3rd note, not the descending B3');
    expect(farThenB.extras.single.midiNote, 80);
    final near = gradeScale(gMajor, [...base, note(60, 0, 1.0)], cfg); // C4 where B3 is due: a slip
    expect(near.notes[2].grade, Grade.red);
    expect(near.notes[2].cents, closeTo(100, 1e-9));
    expect(near.extras, isEmpty);
  });
}
