import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intono_app/src/db/practice_db_open.dart';
import 'package:intono_app/src/db/practice_store.dart';
import 'package:intono_app/src/engine_api.dart';
import 'package:intono_app/src/scales/grader.dart';
import 'package:intono_app/src/scales/grading_config.dart';
import 'package:intono_app/src/scales/scale.dart';

// ADR 0015 decision 1: on the device (the CI emulator and the iOS Simulator), the bundled SQLite opens the real database file on the
// background isolate, a run is written, survives closing and reopening, and Clear history empties it.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the practice database opens, writes, reopens and clears on the device', (t) async {
    final lib = ScaleLibrary.fromJsonString(await rootBundle.loadString('assets/scales/beginner.json'));
    final g = lib.byId('g_major_1oct')!;
    final file = await practiceDbFile();
    if (await file.exists()) await file.delete();

    final played = [
      for (var i = 0; i < g.notes.length; i++)
        Note(
            tStart: 0.5 * i,
            tEnd: 0.5 * i + 0.4,
            midiNote: g.notes[i].midi,
            meanCents: (i % 5) * 3.0,
            stdCents: 2,
            vibratoRateHz: 0,
            vibratoWidthCents: 0,
            meanConfidence: 0.99,
            frameCount: 75)
    ];
    final r = gradeScale(g, played, const GradingConfig());
    final now = DateTime.now().toUtc();

    var store = PracticeStore(await openPracticeDb(), random: math.Random(3));
    final id = await store.saveRun(r, startedAt: now, endedAt: now.add(const Duration(seconds: 8)));
    expect(id, isNotNull);
    await store.close();
    expect(await file.exists(), isTrue);
    expect(await file.length(), greaterThan(0));

    store = PracticeStore(await openPracticeDb());
    final ss = await store.sessions();
    expect(ss.single.id, id);
    expect((await store.gradedNotes(id!)).length, g.notes.length);
    expect(await store.fingerStats(), isNotEmpty);
    await store.clearHistory();
    expect(await store.sessions(), isEmpty);
    await store.close();
    await file.delete();
  });
}
