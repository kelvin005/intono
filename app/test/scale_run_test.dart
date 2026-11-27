import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/engine_api.dart';
import 'package:intono_app/src/scales/grader.dart';
import 'package:intono_app/src/scales/grading_config.dart';
import 'package:intono_app/src/scales/scale.dart';
import 'package:intono_app/src/scales/scale_run.dart';

// ScaleRun (ADR 0011 item 4): the state of one run as the scale screen sees it. Written before the implementation.

final lib = ScaleLibrary.fromJsonString(File('assets/scales/beginner.json').readAsStringSync());
final g = lib.byId('g_major_1oct')!;

Note n(int midi, double cents, double t0, {double ms = 400}) => Note(
    tStart: t0,
    tEnd: t0 + ms / 1000,
    midiNote: midi,
    meanCents: cents,
    stdCents: 2,
    vibratoRateHz: 0,
    vibratoWidthCents: 0,
    meanConfidence: 0.99,
    frameCount: (ms / 5.333).round());

void main() {
  test('before any note: no grade, not complete', () {
    final r = ScaleRun(g, const GradingConfig());
    expect(r.latestGrade, isNull);
    expect(r.complete, isFalse);
    expect(r.playedCount, 0);
  });

  test('the latest grade follows the last graded note', () {
    final r = ScaleRun(g, const GradingConfig());
    r.addNotes([n(55, 0, 0)]);
    expect(r.latestGrade, Grade.green);
    r.addNotes([n(57, 10, 0.5)]);
    expect(r.latestGrade, Grade.yellow);
    r.addNotes([n(59, -30, 1.0)]);
    expect(r.latestGrade, Grade.red);
  });

  test('a far stray note does not change the glance colour; a near wrong note turns it red at once', () {
    final r = ScaleRun(g, const GradingConfig())..addNotes([n(55, 0, 0), n(57, 0, 0.5)]);
    r.addNotes([n(80, 0, 0.8)]); // G#5: a stray, not a slip
    expect(r.latestGrade, Grade.green);
    r.addNotes([n(59, 0, 1.2)]); // B3, the expected 3rd note
    expect(r.latestGrade, Grade.green);
    expect(r.result().extras.single.midiNote, 80);
    final slip = ScaleRun(g, const GradingConfig())..addNotes([n(55, 0, 0), n(57, 0, 0.5), n(60, 0, 1.0)]); // C4 for B3
    expect(slip.latestGrade, Grade.red);
  });

  test('complete once the final note of the scale is played; the result grades the whole run', () {
    final r = ScaleRun(g, const GradingConfig());
    for (var i = 0; i < g.notes.length; i++) {
      expect(r.complete, isFalse);
      r.addNotes([n(g.notes[i].midi, 0, i * 0.5)]);
    }
    expect(r.complete, isTrue);
    final res = r.result();
    expect(res.green, 15);
    expect(res.scorePercent, 100);
  });

  test('the top tonic alone does not complete an ascending-only attempt', () {
    final r = ScaleRun(g, const GradingConfig());
    for (var i = 0; i < g.ascendingCount; i++) {
      r.addNotes([n(g.notes[i].midi, 0, i * 0.5)]);
    }
    expect(r.complete, isFalse, reason: 'the scale ends on the low tonic after the descent');
  });
}
