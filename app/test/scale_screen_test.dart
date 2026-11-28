import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/engine_api.dart';
import 'package:intono_app/src/scales/grader.dart';
import 'package:intono_app/src/scales/grading_config.dart';
import 'package:intono_app/src/scales/scale.dart';
import 'package:intono_app/src/scales/scale_screen.dart';

import 'fake_audio.dart';
import 'fake_engine.dart';

// The scale screen (ADR 0011 item 4): choose a scale, glance view while playing, results with every note coloured, play again.
// Written before the screen.

final lib = ScaleLibrary.fromJsonString(File('assets/scales/beginner.json').readAsStringSync());
final g = lib.byId('g_major_1oct')!;

Note n(int midi, double cents, double t0) => Note(
    tStart: t0,
    tEnd: t0 + 0.4,
    midiNote: midi,
    meanCents: cents,
    stdCents: 2,
    vibratoRateHz: 0,
    vibratoWidthCents: 0,
    meanConfidence: 0.99,
    frameCount: 75);

/// In-tune notes from the start of the scale. Four (27 %) are enough to count as heard (GradingConfig.minHeardFraction, 25 %); eight
/// leave at most half missed, so the run is saved without asking (GradingConfig.badRunFraction, 50 %).
List<Note> heardEnough([int from = 0, int to = 4]) => [for (var i = from; i < to; i++) n(g.notes[i].midi, 0, i * 0.5)];
List<Note> savable() => heardEnough(0, 8);

Widget host(Widget w) => Directionality(textDirection: TextDirection.ltr, child: w);

Color glance(WidgetTester t) => t.widget<ColoredBox>(find.byKey(const Key('glance'))).color;

Finder keyed(String prefix) =>
    find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('$prefix:'));

void main() {
  late FakeAudio audio;
  late FakeEngine engine;
  late List<(ScaleResult, DateTime, DateTime)> saved;
  Widget screen() => host(ScaleScreen(
        audio: audio,
        engineFactory: (_) => engine,
        library: lib,
        config: const GradingConfig(),
        onClose: () {},
        onRunFinished: (r, s, e) async => saved.add((r, s, e)),
      ));

  setUp(() {
    audio = FakeAudio();
    engine = FakeEngine();
    saved = [];
  });

  testWidgets('a finished run is handed to the store once, with its start and end times (ADR 0015)', (t) async {
    await t.pumpWidget(screen());
    await t.tap(find.text('G major, 1 octave'));
    await t.pump();
    await t.pump();
    engine.queuedNotes.addAll([n(55, 1, 0), n(57, 2, 0.5), ...heardEnough(2, 8)]);
    await t.pump(const Duration(milliseconds: 150));
    await t.tap(find.text('Stop'));
    await t.pump();
    expect(saved.length, 1);
    final (r, start, end) = saved.single;
    expect(r.scale.id, 'g_major_1oct');
    expect(r.notes.where((x) => x.played != null).length, 8);
    expect(end.isBefore(start), isFalse);
  });

  testWidgets('the coaching tips appear on the results, after the run is saved (ADR 0016)', (t) async {
    final order = <String>[];
    await t.pumpWidget(host(ScaleScreen(
      audio: audio,
      engineFactory: (_) => engine,
      library: lib,
      config: const GradingConfig(),
      onClose: () {},
      onRunFinished: (r, s, e) async => order.add('saved'),
      coach: (r) async {
        order.add('coach');
        return ['Your 3rd finger on A is often 15¢ sharp. Play F major, 1 octave slowly with the drone.', 'Second tip.'];
      },
    )));
    await t.tap(find.text('G major, 1 octave'));
    await t.pump();
    await t.pump();
    engine.queuedNotes.addAll(savable());
    await t.pump(const Duration(milliseconds: 150));
    await t.tap(find.text('Stop'));
    await t.pump();
    await t.pump();
    expect(order, ['saved', 'coach']);
    expect(find.text('Your 3rd finger on A is often 15¢ sharp. Play F major, 1 octave slowly with the drone.'), findsOneWidget);
    expect(find.text('Second tip.'), findsOneWidget);
  });

  testWidgets('a coaching failure leaves the results without tips', (t) async {
    await t.pumpWidget(host(ScaleScreen(
      audio: audio,
      engineFactory: (_) => engine,
      library: lib,
      config: const GradingConfig(),
      onClose: () {},
      coach: (r) async => throw StateError('db'),
    )));
    await t.tap(find.text('G major, 1 octave'));
    await t.pump();
    await t.pump();
    engine.queuedNotes.addAll(savable());
    await t.pump(const Duration(milliseconds: 150));
    await t.tap(find.text('Stop'));
    await t.pump();
    await t.pump();
    expect(find.text('Play again'), findsOneWidget);
  });

  testWidgets('a store failure is shown on the results and does not hide them', (t) async {
    await t.pumpWidget(host(ScaleScreen(
      audio: audio,
      engineFactory: (_) => engine,
      library: lib,
      config: const GradingConfig(),
      onClose: () {},
      onRunFinished: (r, s, e) async => throw StateError('disk full'),
    )));
    await t.tap(find.text('G major, 1 octave'));
    await t.pump();
    await t.pump();
    engine.queuedNotes.addAll(savable());
    await t.pump(const Duration(milliseconds: 150));
    await t.tap(find.text('Stop'));
    await t.pump();
    await t.pump();
    expect(find.text('Play again'), findsOneWidget);
    expect(find.textContaining('could not be saved'), findsOneWidget);
  });

  testWidgets('the picker lists every scale', (t) async {
    await t.pumpWidget(screen());
    expect(find.text('G major, 1 octave'), findsOneWidget);
    expect(find.text('A melodic minor, 2 octaves'), findsOneWidget);
    expect(keyed('scale-tile'), findsNWidgets(lib.scales.length));
  });

  testWidgets('choosing a scale starts capture; the glance view is neutral until the first note', (t) async {
    await t.pumpWidget(screen());
    await t.tap(find.text('G major, 1 octave'));
    await t.pump();
    await t.pump();
    expect(audio.started, isTrue);
    expect(glance(t), ScaleColors.neutral);
    expect(find.text('Stop'), findsOneWidget);
  });

  testWidgets('a run gives the engine the scale as its expected sequence, and Stop returns it to free mode (ADR 0014)', (t) async {
    await t.pumpWidget(screen());
    await t.tap(find.text('G major, 1 octave'));
    await t.pump();
    await t.pump();
    expect(engine.expectedCalls, [
      [for (final s in g.notes) s.midi]
    ]);
    await t.tap(find.text('Stop'));
    await t.pump();
    expect(engine.expectedCalls.last, isEmpty);
  });

  testWidgets('the whole screen takes the grade of the last note', (t) async {
    await t.pumpWidget(screen());
    await t.tap(find.text('G major, 1 octave'));
    await t.pump();
    await t.pump();
    engine.queuedNotes.add(n(55, 1, 0));
    await t.pump(const Duration(milliseconds: 150));
    expect(glance(t), ScaleColors.green);
    engine.queuedNotes.add(n(57, 12, 0.5));
    await t.pump(const Duration(milliseconds: 150));
    expect(glance(t), ScaleColors.yellow);
    engine.queuedNotes.add(n(59, -40, 1.0));
    await t.pump(const Duration(milliseconds: 150));
    expect(glance(t), ScaleColors.red);
  });

  testWidgets('the last note of the scale ends the run: results with the score, the counts and every note', (t) async {
    await t.pumpWidget(screen());
    await t.tap(find.text('G major, 1 octave'));
    await t.pump();
    await t.pump();
    for (var i = 0; i < g.notes.length; i++) {
      engine.queuedNotes.add(n(g.notes[i].midi, i == 3 ? 10 : 0, i * 0.5));
    }
    await t.pump(const Duration(milliseconds: 150));
    await t.pump();
    await t.pump();
    expect(audio.calls, contains('freeze'), reason: 'the microphone stops feeding the engine with the run (ADR 0013: review)');
    expect(find.text('97 %'), findsOneWidget); // (14 + 0.5) / 15 = 96.7
    expect(find.text('🟢 14   🟡 1   🔴 0'), findsOneWidget);
    expect(keyed('result-note'), findsNWidgets(15));
    expect(find.textContaining('C4'), findsWidgets);
    expect(find.text('Play again'), findsOneWidget);
  });

  testWidgets('Stop ends the run early: unplayed notes are missed', (t) async {
    await t.pumpWidget(screen());
    await t.tap(find.text('G major, 1 octave'));
    await t.pump();
    await t.pump();
    engine.queuedNotes.addAll(heardEnough());
    await t.pump(const Duration(milliseconds: 150));
    await t.tap(find.text('Stop'));
    await t.pump();
    await t.pump();
    expect(find.text('🟢 4   🟡 0   🔴 11'), findsOneWidget);
    expect(find.text('27 %'), findsOneWidget);
  });

  testWidgets('Play again starts the same scale with a fresh run', (t) async {
    await t.pumpWidget(screen());
    await t.tap(find.text('G major, 1 octave'));
    await t.pump();
    await t.pump();
    await t.tap(find.text('Stop'));
    await t.pump();
    await t.pump();
    await t.tap(find.text('Play again'));
    await t.pump();
    await t.pump();
    expect(audio.started, isTrue);
    expect(glance(t), ScaleColors.neutral);
    expect(find.text('G major, 1 octave'), findsOneWidget);
  });

  testWidgets('no microphone: says so on the picker', (t) async {
    audio.startResult = false;
    await t.pumpWidget(screen());
    await t.tap(find.text('G major, 1 octave'));
    await t.pump();
    await t.pump();
    await t.pump();
    expect(find.textContaining('no microphone permission'), findsOneWidget);
    expect(keyed('scale-tile'), findsWidgets);
  });

  group('a note far from the expected one shows the nearest semitone (ADR 0018 note)', () {
    Future<void> playAndStop(WidgetTester t, List<Note> notes) async {
      await t.pumpWidget(screen());
      await t.tap(find.text('G major, 1 octave'));
      await t.pump();
      await t.pump();
      engine.queuedNotes.addAll([...notes, n(59, 0, 1.0), n(60, 0, 1.5)]); // four notes: enough to count as heard
      await t.pump(const Duration(milliseconds: 150));
      await t.tap(find.text('Stop'));
      await t.pump();
    }

    testWidgets('55 cents flat: "sounds closer to F#" in that note\'s result cell, and only there', (t) async {
      await playAndStop(t, [n(55, -55, 0), n(57, 2, 0.5)]);
      expect(find.text('G3\n-55¢\nG open\nsounds closer to F#'), findsOneWidget);
      expect(find.textContaining('sounds closer to'), findsOneWidget);
    });

    testWidgets('45 cents sharp: "almost G#"', (t) async {
      await playAndStop(t, [n(55, 45, 0), n(57, 2, 0.5)]);
      expect(find.textContaining('almost G#'), findsOneWidget);
      expect(find.textContaining('sounds closer to'), findsNothing);
    });

    testWidgets('30 cents off: no hint', (t) async {
      await playAndStop(t, [n(55, 30, 0), n(57, 2, 0.5)]);
      expect(find.textContaining('closer to'), findsNothing);
      expect(find.textContaining('almost'), findsNothing);
    });
  });

  group('what a run is worth (Kelechi phone test, 2026-11-28)', () {
    Future<void> playAndStop(WidgetTester t, List<Note> notes, {Future<List<String>> Function(ScaleResult)? coach}) async {
      await t.pumpWidget(host(ScaleScreen(
        audio: audio,
        engineFactory: (_) => engine,
        library: lib,
        config: const GradingConfig(),
        onClose: () {},
        onRunFinished: (r, s, e) async => saved.add((r, s, e)),
        coach: coach,
      )));
      await t.tap(find.text('G major, 1 octave'));
      await t.pump();
      await t.pump();
      engine.queuedNotes.addAll(notes);
      await t.pump(const Duration(milliseconds: 150));
      await t.tap(find.text('Stop'));
      await t.pump();
      await t.pump();
    }

    testWidgets("silence: \"I didn't hear you play\", no grade, nothing saved, no tips", (t) async {
      var coached = 0;
      await playAndStop(t, const [], coach: (r) async {
        coached++;
        return ['a tip'];
      });
      expect(find.textContaining("I didn't hear you play"), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.text('a tip'), findsNothing);
      expect(saved, isEmpty);
      expect(coached, 0);
      expect(find.text('Play again'), findsOneWidget);
    });

    testWidgets('a wrong note is named with its expected note, with no cents', (t) async {
      await playAndStop(t, [n(64, 0, 0), for (var i = 1; i < 9; i++) n(g.notes[i].midi, 0, i * 0.6)]); // E4 where G3 was due, then 8 right
      expect(find.textContaining('played E4, expected G3'), findsOneWidget);
      expect(find.textContaining('+0¢'), findsWidgets);
      expect(find.textContaining('1029'), findsNothing);
      expect(saved.length, 1);
    });

    testWidgets('more than half missed or wrong: results are shown, "Save this run?" is asked, nothing is saved until Save', (t) async {
      await playAndStop(t, [for (var i = 0; i < 10; i++) n(73, 0, i * 0.6)]); // C#5, ten times
      expect(find.textContaining('Save this run?'), findsOneWidget);
      expect(find.text("Don't save"), findsOneWidget);
      expect(saved, isEmpty);
      await t.tap(find.text('Save'));
      await t.pump();
      expect(saved.length, 1);
      expect(find.textContaining('Save this run?'), findsNothing);
    });

    testWidgets('"Don\'t save" keeps the run out of the history and out of the tips', (t) async {
      var coached = 0;
      await playAndStop(t, [for (var i = 0; i < 10; i++) n(73, 0, i * 0.6)], coach: (r) async {
        coached++;
        return ['a tip'];
      });
      await t.tap(find.text("Don't save"));
      await t.pump();
      await t.pump();
      expect(saved, isEmpty);
      expect(coached, 0);
      expect(find.textContaining('Not saved'), findsOneWidget);
    });
  });
}
