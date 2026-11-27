import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/engine_api.dart';
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

Widget host(Widget w) => Directionality(textDirection: TextDirection.ltr, child: w);

Color glance(WidgetTester t) => t.widget<ColoredBox>(find.byKey(const Key('glance'))).color;

Finder keyed(String prefix) =>
    find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('$prefix:'));

void main() {
  late FakeAudio audio;
  late FakeEngine engine;
  Widget screen() => host(ScaleScreen(
        audio: audio,
        engineFactory: (_) => engine,
        library: lib,
        config: const GradingConfig(),
        onClose: () {},
      ));

  setUp(() {
    audio = FakeAudio();
    engine = FakeEngine();
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
    expect(audio.started, isFalse, reason: 'capture stops with the run');
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
    engine.queuedNotes.addAll([n(55, 0, 0), n(57, 0, 0.5)]);
    await t.pump(const Duration(milliseconds: 150));
    await t.tap(find.text('Stop'));
    await t.pump();
    await t.pump();
    expect(find.text('🟢 2   🟡 0   🔴 13'), findsOneWidget);
    expect(find.text('13 %'), findsOneWidget);
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
}
