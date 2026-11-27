import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/debug_screen.dart';

import 'fake_audio.dart';
import 'fake_engine.dart';

Widget host(Widget child) => Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  testWidgets('stopped first; Start opens the engine at the pointer the platform gave and shows the live pitch', (tester) async {
    final audio = FakeAudio();
    final engine = FakeEngine();
    int? usedPointer;
    await tester.pumpWidget(host(DebugScreen(
      audio: audio,
      engineFactory: (p) {
        usedPointer = p;
        return engine;
      },
    )));
    await tester.pump();
    expect(find.text('stopped'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    expect(usedPointer, 4242);

    engine.queuedFrames.add(frame(midi: 69, cents: 3.04));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('A4'), findsOneWidget);
    expect(find.text('+3.0'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    await tester.pump();
    expect(audio.started, isFalse);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
  });

  testWidgets('a failed start shows the platform error and keeps the Start button', (tester) async {
    final audio = FakeAudio()..startResult = false;
    await tester.pumpWidget(host(DebugScreen(audio: audio, engineFactory: (_) => FakeEngine())));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('no microphone permission'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('the drone switch is off by default, asks the platform, and warns on the speaker', (tester) async {
    final audio = FakeAudio();
    await tester.pumpWidget(host(DebugScreen(audio: audio, engineFactory: (_) => FakeEngine())));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    expect(audio.drone, isNull);
    await tester.tap(find.text('Drone: off'));
    await tester.pump();
    await tester.pump();
    expect(audio.drone, isTrue);
    expect(find.text('Drone: on'), findsOneWidget);
    expect(find.text('Use headphones for accurate results'), findsOneWidget);
  });

  testWidgets('with headphones the drone is on by default and there is no warning', (tester) async {
    final audio = FakeAudio()..headphones = true;
    await tester.pumpWidget(host(DebugScreen(audio: audio, engineFactory: (_) => FakeEngine())));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    expect(audio.drone, isTrue);
    expect(find.text('Drone: on'), findsOneWidget);
    expect(find.text('Use headphones for accurate results'), findsNothing);
  });

  testWidgets('capture stops when the app is hidden, before the engine can go away', (tester) async {
    final audio = FakeAudio();
    await tester.pumpWidget(host(DebugScreen(audio: audio, engineFactory: (_) => FakeEngine())));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    expect(audio.started, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();
    expect(audio.started, isFalse);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('the stream facts refresh twice a second while running, and stop refreshing after Stop', (tester) async {
    final audio = FakeAudio()..infoText = 'hops 1';
    await tester.pumpWidget(host(DebugScreen(audio: audio, engineFactory: (_) => FakeEngine())));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    expect(find.text('hops 1'), findsOneWidget);

    audio.infoText = 'hops 2';
    await tester.pump(const Duration(milliseconds: 520));
    await tester.pump();
    expect(find.text('hops 2'), findsOneWidget);

    audio.infoText = 'hops 3';
    await tester.pump(const Duration(milliseconds: 520));
    await tester.pump();
    expect(find.text('hops 3'), findsOneWidget);

    await tester.tap(find.text('Stop'));
    await tester.pump();
    await tester.pump();
    audio.started = true; // a late timer tick must not resurrect the panel
    audio.infoText = 'hops 4';
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('hops 4'), findsNothing);
    expect(find.text('stopped'), findsOneWidget);
  });

  testWidgets('the refresh timer is cancelled when the screen goes away while running', (tester) async {
    final audio = FakeAudio();
    await tester.pumpWidget(host(DebugScreen(audio: audio, engineFactory: (_) => FakeEngine())));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    await tester.pumpWidget(host(const SizedBox()));   // a pending periodic timer would fail the test at its end
  });

  testWidgets('a long press on the version label stops capture and opens the bench', (tester) async {
    final audio = FakeAudio();
    var opened = 0;
    await tester.pumpWidget(host(DebugScreen(audio: audio, engineFactory: (_) => FakeEngine(), onOpenBench: () => opened++)));
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();
    expect(audio.started, isTrue);

    await tester.tap(find.byKey(const Key('version-label')));   // a tap does nothing
    await tester.pump();
    expect(opened, 0);

    await tester.longPress(find.byKey(const Key('version-label')));
    await tester.pump();
    await tester.pump();
    expect(audio.started, isFalse);   // the bench needs the device quiet, and the engine must not outlive the stream
    expect(opened, 1);
  });
}
