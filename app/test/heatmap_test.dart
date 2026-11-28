import 'dart:io';
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/db/practice_db.dart';
import 'package:intono_app/src/db/practice_stats.dart';
import 'package:intono_app/src/db/practice_store.dart';
import 'package:intono_app/src/engine_api.dart';
import 'package:intono_app/src/heatmap/heatmap.dart';
import 'package:intono_app/src/heatmap/heatmap_screen.dart';
import 'package:intono_app/src/scales/grader.dart';
import 'package:intono_app/src/scales/grading_config.dart';
import 'package:intono_app/src/scales/scale.dart';

// The finger-level heatmap (architecture doc, "Coaching"): computed from graded_notes, per (string, finger, placement), over the last
// 30 days. Written before the heatmap.

StoredNote sn(int idx, String string, int finger, String? placement, double? cents, {int midi = 60}) => StoredNote(
    idx: idx,
    midiNote: midi,
    string: string,
    finger: finger,
    placement: placement,
    grade: cents == null ? Grade.missed : gradeOfCents(cents, const GradingConfig()),
    cents: cents,
    tStart: cents == null ? null : 0.5 * idx,
    tEnd: cents == null ? null : 0.5 * idx + 0.4);

Widget host(Widget w) => Directionality(textDirection: TextDirection.ltr, child: MediaQuery(data: const MediaQueryData(), child: w));

void main() {
  group('heatmapOf', () {
    test('groups by string, finger and placement, with played notes only in the cents', () {
      final cells = heatmapOf([
        ('s1', sn(0, 'A', 3, 'high', 12)),
        ('s1', sn(1, 'A', 3, 'high', 18)),
        ('s2', sn(0, 'A', 3, 'high', 15)),
        ('s2', sn(1, 'A', 3, 'high', null)),
        ('s1', sn(2, 'A', 3, 'low', -4)),
        ('s2', sn(2, 'D', 0, null, 1)),
      ]);
      expect(cells.length, 3);
      final a3 = cells.singleWhere((c) => c.string == 'A' && c.finger == 3 && c.placement == 'high');
      expect([a3.count, a3.played, a3.missed, a3.sessions], [4, 3, 1, 2]);
      expect(a3.meanCents, closeTo(15, 1e-9));
      expect(a3.meanAbsCents, closeTo(15, 1e-9));
      final xs = [12.0, 18.0, 15.0];
      expect(a3.stdCents, closeTo(math.sqrt(xs.map((x) => (x - 15) * (x - 15)).reduce((a, b) => a + b) / 3), 1e-9));
      expect(cells.singleWhere((c) => c.placement == 'low').meanCents, closeTo(-4, 1e-9));
    });

    test('a cell with only missed notes has no cents', () {
      final c = heatmapOf([('s', sn(0, 'E', 1, 'low', null))]).single;
      expect(c.played, 0);
      expect(c.meanCents, isNull);
      expect(c.meanAbsCents, isNull);
    });

    test('cells come in fingerboard order: string G D A E, then finger, then low, natural, high', () {
      final cells = heatmapOf([
        ('s', sn(0, 'E', 0, null, 0)),
        ('s', sn(1, 'G', 2, 'high', 0)),
        ('s', sn(2, 'G', 2, 'low', 0)),
        ('s', sn(3, 'G', 0, null, 0)),
        ('s', sn(4, 'D', 1, null, 0)),
      ]);
      expect(cells.map((c) => '${c.string}${c.finger}${c.placement ?? ''}'), ['G0', 'G2low', 'G2high', 'D1', 'E0']);
    });

    test('a cell is coloured by the grader thresholds on its mean absolute error', () {
      final cells = heatmapOf([
        ('s', sn(0, 'A', 1, 'low', 3)),
        ('s', sn(1, 'A', 2, 'high', 10)),
        ('s', sn(2, 'A', 3, 'high', -25)),
        ('s', sn(3, 'A', 4, null, null)),
      ]);
      const cfg = GradingConfig();
      expect(cells.map((c) => c.grade(cfg)), [Grade.green, Grade.yellow, Grade.red, null]);
    });

    test('the sentence follows the doc: string, finger, average, sessions', () {
      final c = heatmapOf([
        ('s1', sn(0, 'A', 3, 'high', 14)),
        ('s2', sn(0, 'A', 3, 'high', 16)),
      ]).single;
      expect(c.describe(), 'A string, 3rd finger (high): average +15¢ over 2 notes in 2 sessions');
      final o = heatmapOf([('s', sn(0, 'D', 0, null, -2.4))]).single;
      expect(o.describe(), 'D string, open: average −2¢ over 1 note in 1 session');
    });
  });

  group('the store', () {
    late PracticeStore store;
    final lib = ScaleLibrary.fromJsonString(File('assets/scales/beginner.json').readAsStringSync());
    final g = lib.byId('g_major_1oct')!;
    var t = DateTime.utc(2026, 11, 1, 9);

    setUp(() {
      t = DateTime.utc(2026, 11, 1, 9);
      store = PracticeStore(PracticeDb(NativeDatabase.memory()), clock: () => t, random: math.Random(5));
    });
    tearDown(() => store.close());

    Future<void> runAt(DateTime at, double cents) async {
      t = at;
      final notes = [
        for (var i = 0; i < g.notes.length; i++)
          Note(
              tStart: 0.5 * i,
              tEnd: 0.5 * i + 0.4,
              midiNote: g.notes[i].midi,
              meanCents: cents,
              stdCents: 2,
              vibratoRateHz: 0,
              vibratoWidthCents: 0,
              meanConfidence: 0.99,
              frameCount: 75)
      ];
      await store.saveRun(gradeScale(g, notes, const GradingConfig()), startedAt: at, endedAt: at.add(const Duration(seconds: 8)));
    }

    test('gradedNotesSince keeps only sessions that started inside the window, from graded_notes', () async {
      await runAt(DateTime.utc(2026, 10, 1), 30); // older than 30 days on 2026-11-27
      await runAt(DateTime.utc(2026, 11, 20), 4);
      await runAt(DateTime.utc(2026, 11, 26), 6);
      final rows = await store.gradedNotesSince(DateTime.utc(2026, 10, 28));
      expect(rows.length, 2 * g.notes.length);
      final cells = heatmapOf(rows);
      final open = cells.singleWhere((c) => c.string == 'G' && c.finger == 0);
      expect(open.sessions, 2);
      expect(open.meanCents, closeTo(5, 1e-9));
    });

    test('the heatmap follows a threshold change at once: it re-grades from graded_notes, not from the caches', () async {
      await runAt(DateTime.utc(2026, 11, 20), 8);
      final cells = heatmapOf(await store.gradedNotesSince(DateTime.utc(2026, 11, 1)));
      expect(cells.first.grade(const GradingConfig()), Grade.yellow);
      expect(cells.first.grade(const GradingConfig(greenCents: 10, yellowCents: 25)), Grade.green);
    });
  });

  group('the screen', () {
    List<HeatCell> sample() => heatmapOf([
          ('s1', sn(0, 'A', 3, 'high', 14)),
          ('s2', sn(0, 'A', 3, 'high', 16)),
          ('s1', sn(1, 'D', 0, null, 1)),
        ]);

    testWidgets('shows a cell per string and finger with its average, and the sentence when tapped', (t) async {
      var closed = 0;
      await t.pumpWidget(host(HeatmapScreen(load: () async => sample(), config: const GradingConfig(), onClose: () => closed++)));
      await t.pump();
      expect(find.text('Last 30 days'), findsOneWidget);
      for (final s in ['G', 'D', 'A', 'E']) {
        expect(find.text(s), findsOneWidget);
      }
      expect(find.text('+15¢'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('heat:A:3:high')));
      await t.pump();
      expect(find.text('A string, 3rd finger (high): average +15¢ over 2 notes in 2 sessions'), findsOneWidget);
      await t.tap(find.text('Back'));
      expect(closed, 1);
    });

    testWidgets('with no history it says so', (t) async {
      await t.pumpWidget(host(HeatmapScreen(load: () async => const [], config: const GradingConfig(), onClose: () {})));
      await t.pump();
      expect(find.textContaining('No graded notes'), findsOneWidget);
    });

    testWidgets('a load failure is shown, not hidden', (t) async {
      await t.pumpWidget(host(HeatmapScreen(load: () async => throw StateError('db'), config: const GradingConfig(), onClose: () {})));
      await t.pump();
      expect(find.textContaining('could not be loaded'), findsOneWidget);
    });
  });
}
