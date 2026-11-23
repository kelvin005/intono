import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/audio_control.dart';
import 'package:intono_app/src/debug_screen.dart';

import 'fake_engine.dart';

class FakeAudio implements AudioControl {
  bool started = false;
  bool startResult = true;
  bool? drone;
  int pointer = 4242;

  @override
  Future<bool> start() async => started = startResult;

  @override
  Future<void> stop() async => started = false;

  @override
  Future<int> enginePointer() async => started ? pointer : 0;

  @override
  Future<bool> setDrone(bool on, {int midiNote = 57, double gain = 0.3}) async {
    drone = on;
    return true;
  }

  @override
  Future<String> info() async => started ? 'input: AAudio, Exclusive, 48000 Hz' : 'stopped';

  @override
  Future<String> lastError() async => started ? '' : 'no microphone permission';
}

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
    expect(find.text('A4  +3.0'), findsOneWidget);
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
}
