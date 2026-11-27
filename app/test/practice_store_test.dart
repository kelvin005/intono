import 'dart:io';
import 'dart:math' as math;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/db/practice_db.dart';
import 'package:intono_app/src/db/practice_stats.dart';
import 'package:intono_app/src/db/practice_store.dart';
import 'package:intono_app/src/engine_api.dart';
import 'package:intono_app/src/scales/grader.dart';
import 'package:intono_app/src/scales/grading_config.dart';
import 'package:intono_app/src/scales/scale.dart';

// The local practice database (ADR 0015), on an in-memory SQLite. Written before the store.

final lib = ScaleLibrary.fromJsonString(File('assets/scales/beginner.json').readAsStringSync());
final g = lib.byId('g_major_1oct')!; // G3 A3 B3 C4 D4 E4 F#4 G4 F#4 E4 D4 C4 B3 A3 G3

Note n(int midi, double cents, double t0, {double dur = 0.4}) => Note(
    tStart: t0,
    tEnd: t0 + dur,
    midiNote: midi,
    meanCents: cents,
    stdCents: 2,
    vibratoRateHz: 0,
    vibratoWidthCents: 0,
    meanConfidence: 0.99,
    frameCount: 75);

/// The scale played with the given cents per position (null: not played), 0.5 s apart.
ScaleResult play(List<double?> cents, {GradingConfig cfg = const GradingConfig()}) {
  final notes = <Note>[];
  for (var i = 0; i < g.notes.length; i++) {
    final c = cents[i];
    if (c != null) notes.add(n(g.notes[i].midi, c, 0.5 * i));
  }
  return gradeScale(g, notes, cfg);
}

// green 5, yellow 15: positions 0-14
const cents = <double?>[1, -3, 8, 12, -20, 0, 4, null, 6, -2, 30, 2, -4, 1, 0];

void main() {
  late PracticeDb db;
  late PracticeStore store;
  var t = DateTime.utc(2026, 11, 27, 9);

  setUp(() {
    db = PracticeDb(NativeDatabase.memory());
    t = DateTime.utc(2026, 11, 27, 9);
    store = PracticeStore(db, clock: () => t, random: math.Random(7));
  });
  tearDown(() => store.close());

  Future<String> save(ScaleResult r) async {
    final id = await store.saveRun(r, startedAt: t, endedAt: t.add(const Duration(seconds: 8)));
    t = t.add(const Duration(minutes: 1));
    return id!;
  }

  test('a graded run becomes one graded_notes row per scale position, with mapping, grade, cents and timing', () async {
    final id = await save(play(cents));
    final rows = await store.gradedNotes(id);
    expect(rows.length, 15);
    expect(rows.map((r) => r.idx), List.generate(15, (i) => i));
    expect(rows.map((r) => r.midiNote), g.notes.map((s) => s.midi));
    expect(rows[2].string, 'G');
    expect(rows[2].finger, 2);
    expect(rows[2].placement, 'high');
    expect(rows[4].string, 'D');
    expect(rows[4].finger, 0);
    expect(rows[4].placement, isNull);
    expect(rows[0].grade, Grade.green);
    expect(rows[2].grade, Grade.yellow);
    expect(rows[4].grade, Grade.red);
    expect(rows[4].cents, closeTo(-20, 1e-9));
    expect(rows[3].tStart, closeTo(1.5, 1e-9));
    expect(rows[3].tEnd, closeTo(1.9, 1e-9));
  });

  test('a missed note is stored as missed, with no cents and no timing', () async {
    final id = await save(play(cents));
    final r = (await store.gradedNotes(id))[7];
    expect(r.grade, Grade.missed);
    expect(r.cents, isNull);
    expect(r.tStart, isNull);
    expect(r.tEnd, isNull);
  });

  test('the session totals and note_stats are exactly what the graded notes give', () async {
    final res = play(cents);
    final id = await save(res);
    final s = (await store.sessions()).single;
    final notes = await store.gradedNotes(id);
    final tot = totalsOf(notes);
    expect([s.totals.green, s.totals.yellow, s.totals.red, s.totals.missed, s.totals.noteCount],
        [tot.green, tot.yellow, tot.red, tot.missed, tot.noteCount]);
    expect([res.green, res.yellow, res.red, res.missed], [tot.green, tot.yellow, tot.red, tot.missed]);
    expect(s.scorePercent, closeTo(res.scorePercent, 1e-9));
    expect(s.instrument, 'violin');
    expect(s.scaleId, 'g_major_1oct');
    final stats = await store.noteStats(id);
    final want = noteStatsOf(notes);
    expect(stats.length, want.length);
    for (var i = 0; i < want.length; i++) {
      expect(
          [stats[i].midiNote, stats[i].string, stats[i].finger, stats[i].placement, stats[i].count, stats[i].missed],
          [want[i].midiNote, want[i].string, want[i].finger, want[i].placement, want[i].count, want[i].missed]);
      expect(stats[i].meanCents, want[i].meanCents == null ? isNull : closeTo(want[i].meanCents!, 1e-9));
    }
  });

  test('the same note on the same finger going up and down is one note_stats row with both', () async {
    final id = await save(play(cents));
    final stats = await store.noteStats(id);
    expect(stats.length, 8); // G3 A3 B3 C4 D4 E4 F#4 G4
    final b3 = stats.singleWhere((s) => s.midiNote == 59);
    expect(b3.count, 2);
    expect(b3.placement, 'high');
    expect(b3.meanCents, closeTo((8 + -4) / 2, 1e-9));
    expect(b3.meanAbsCents, closeTo((8 + 4) / 2, 1e-9));
    expect(b3.stdCents, closeTo(6, 1e-9));
    expect(b3.totalMs, closeTo(800, 1e-6));
    final g4 = stats.singleWhere((s) => s.midiNote == 67);
    expect([g4.count, g4.missed], [1, 1]);
    expect(g4.meanCents, isNull);
    expect(g4.totalMs, 0);
    final open = stats.singleWhere((s) => s.midiNote == 55);
    expect(open.placement, ''); // none (part of the key)
  });

  test('sessions are append-only: a second run adds a session and leaves the first untouched', () async {
    final a = await save(play(cents));
    final before = await store.gradedNotes(a);
    final b = await save(play(List<double?>.filled(15, 0)));
    expect(a, isNot(b));
    final ss = await store.sessions();
    expect(ss.map((s) => s.id), [b, a]); // newest first
    final after = await store.gradedNotes(a);
    expect(after.map((r) => r.cents), before.map((r) => r.cents));
    expect(after.map((r) => r.grade), before.map((r) => r.grade));
  });

  test('a run with no played note is not stored', () async {
    final id = await store.saveRun(play(List<double?>.filled(15, null)), startedAt: t, endedAt: t);
    expect(id, isNull);
    expect(await store.sessions(), isEmpty);
  });

  test('rebuilding the caches after a threshold change re-grades the stored cents; missed stays missed', () async {
    final id = await save(play(cents));
    await store.rebuildCaches(const GradingConfig(greenCents: 10, yellowCents: 25), lib);
    final rows = await store.gradedNotes(id);
    expect(rows[2].grade, Grade.green); // 8 cents: was yellow
    expect(rows[4].grade, Grade.yellow); // -20: was red
    expect(rows[10].grade, Grade.red); // 30: still red
    expect(rows[7].grade, Grade.missed);
    final s = (await store.sessions()).single;
    final tot = totalsOf(rows);
    expect([s.totals.green, s.totals.yellow, s.totals.red, s.totals.missed], [tot.green, tot.yellow, tot.red, tot.missed]);
    expect(s.scorePercent, closeTo(tot.scorePercent, 1e-9));
    final b3 = (await store.noteStats(id)).singleWhere((x) => x.midiNote == 59);
    expect(b3.green, 2);
  });

  test('rebuilding re-maps string, finger and placement from the current scale data', () {
    final notes = storedNotesOf(play(cents));
    final wrong = [for (final x in notes) x.idx == 2 ? x.copyWith(string: 'D', finger: 4, clearPlacement: true) : x];
    final fixed = regrade(wrong, const GradingConfig(), g);
    expect([fixed[2].string, fixed[2].finger, fixed[2].placement], ['G', 2, 'high']);
    final noScale = regrade(wrong, const GradingConfig(), null);
    expect([noScale[2].string, noScale[2].finger], ['D', 4]); // a scale no longer shipped: the stored mapping stands
  });

  test('Clear history leaves no session, graded note or statistic, and keeps settings', () async {
    await save(play(cents));
    await save(play(cents));
    await store.setSetting('drone', 'on');
    await store.clearHistory();
    expect(await store.sessions(), isEmpty);
    for (final table in ['sessions', 'graded_notes', 'note_stats']) {
      final c = await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle();
      expect(c.read<int>('c'), 0, reason: table);
    }
    expect(await store.setting('drone'), 'on');
    expect(await store.fingerStats(), isEmpty);
  });

  test('fingerStats pools every session per (string, finger, placement), for the heatmap', () async {
    await save(play(cents));
    await save(play(List<double?>.filled(15, 10)));
    final f = await store.fingerStats();
    final g2 = f.singleWhere((x) => x.string == 'G' && x.finger == 2 && x.placement == 'high');
    expect(g2.count, 4); // B3 twice per run
    expect(g2.played, 4);
    expect(g2.meanCents, closeTo((8 - 4 + 10 + 10) / 4, 1e-9));
    final xs = [8.0, -4.0, 10.0, 10.0];
    final m = xs.reduce((a, b) => a + b) / 4;
    expect(g2.stdCents, closeTo(math.sqrt(xs.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / 4), 1e-9));
    final d3 = f.singleWhere((x) => x.string == 'D' && x.finger == 3); // G4: missed in the first run
    expect([d3.count, d3.missed, d3.played], [2, 1, 1]);
    expect(d3.meanCents, closeTo(10, 1e-9));
    expect(f.first.string, 'G');
    expect(f.first.finger, 0);
  });

  test('settings: a value is stored and replaced', () async {
    expect(await store.setting('x'), isNull);
    await store.setSetting('x', '1');
    await store.setSetting('x', '2');
    expect(await store.setting('x'), '2');
  });

  test('session ids are UUIDv7: version 7, the RFC variant, ordered by time', () {
    final r = math.Random(1);
    final a = uuidV7(DateTime.utc(2026, 11, 27, 9), r);
    final b = uuidV7(DateTime.utc(2026, 11, 27, 9, 0, 1), r);
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(a), isTrue, reason: a);
    expect(a.compareTo(b), lessThan(0));
    final ms = int.parse(a.replaceAll('-', '').substring(0, 12), radix: 16);
    expect(ms, DateTime.utc(2026, 11, 27, 9).millisecondsSinceEpoch);
  });

  test('foreign keys are on: graded notes cannot point at a missing session', () async {
    await expectLater(
      db.customStatement("INSERT INTO graded_notes (session_id, idx, midi_note, string, finger, grade) VALUES ('nope', 0, 55, 'G', 0, 'green')"),
      throwsA(anything),
    );
  });
}
