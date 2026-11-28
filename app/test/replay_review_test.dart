import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/engine_api.dart';
import 'package:intono_app/src/scales/grading_config.dart';
import 'package:intono_app/src/scales/scale.dart';
import 'package:intono_app/src/scales/scale_screen.dart';

import 'fake_audio.dart';
import 'fake_engine.dart';

// Replay on the review screen (ADR 0013), written before the screen code: the ring is armed with each run, frozen at its end, played
// per note or whole, and released (zeroed in the shim) when the review ends, the app goes to the background, a new run starts or the
// screen closes.

final lib = ScaleLibrary.fromJsonString(File('assets/scales/beginner.json').readAsStringSync());
final g = lib.byId('g_major_1oct')!;

Widget host(Widget w) => Directionality(textDirection: TextDirection.ltr, child: MediaQuery(data: const MediaQueryData(), child: w));

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

void main() {
  late FakeAudio audio;
  late FakeEngine engine;
  var closed = 0;
  Widget screen() => host(ScaleScreen(
        audio: audio,
        engineFactory: (_) => engine,
        library: lib,
        config: const GradingConfig(),
        onClose: () => closed++,
      ));

  setUp(() {
    audio = FakeAudio();
    engine = FakeEngine();
    closed = 0;
  });

  Future<void> runAndStop(WidgetTester t, {int played = 4}) async {
    await t.pumpWidget(screen());
    await t.tap(find.text('G major, 1 octave'));
    await t.pump();
    await t.pump();
    for (var i = 0; i < played; i++) {
      engine.queuedNotes.add(n(g.notes[i].midi, 0, 2.0 + 0.5 * i));
    }
    await t.pump(const Duration(milliseconds: 150));
    await t.tap(find.text('Stop'));
    await t.pump();
    await t.pump();
  }

  testWidgets('a run arms the ring after capture starts, and its end freezes it without closing the session', (t) async {
    await runAndStop(t);
    expect(audio.calls.take(2), ['arm', 'freeze']);
    expect(audio.started, isTrue, reason: 'the output path stays open for playback');
    expect(find.text('Play the run'), findsOneWidget);
  });

  testWidgets('tapping a played note plays its own slice, with 50 ms either side', (t) async {
    await runAndStop(t);
    await t.tap(find.byKey(const ValueKey('result-note:1')));
    await t.pump();
    expect(audio.calls.last, 'play 2.450-2.950'); // A3: 2.5 to 2.9 s
  });

  testWidgets('a missed note has nothing to play', (t) async {
    await runAndStop(t);
    final before = audio.calls.length;
    await t.tap(find.byKey(const ValueKey('result-note:9')));
    await t.pump();
    expect(audio.calls.length, before);
  });

  testWidgets('Play the run plays from the first played note to the last', (t) async {
    await runAndStop(t);
    await t.tap(find.text('Play the run'));
    await t.pump();
    expect(audio.calls.last, 'play 1.800-4.200'); // 2.0 - 0.2 to 3.9 + 0.3
  });

  testWidgets('while it plays, Stop playback stops it', (t) async {
    await runAndStop(t);
    await t.tap(find.text('Play the run'));
    await t.pump();
    expect(find.text('Stop playback'), findsOneWidget);
    await t.tap(find.text('Stop playback'));
    await t.pump();
    expect(audio.calls.last, 'stop-playback');
    expect(find.text('Play the run'), findsOneWidget);
  });

  testWidgets('when playback ends by itself the button comes back', (t) async {
    await runAndStop(t);
    await t.tap(find.text('Play the run'));
    await t.pump();
    audio.playing = false;
    await t.pump(const Duration(milliseconds: 300));
    await t.pump();
    expect(find.text('Play the run'), findsOneWidget);
  });

  testWidgets('leaving the review for the scales releases the ring, then closes the session', (t) async {
    await runAndStop(t);
    await t.tap(find.text('Scales'));
    await t.pump();
    await t.pump();
    final i = audio.calls.indexOf('release');
    expect(i, greaterThan(0));
    expect(audio.calls.sublist(i).take(2), ['release', 'stop']);
    expect(audio.armed, isFalse);
  });

  testWidgets('Play again releases the old run before the new one is armed', (t) async {
    await runAndStop(t);
    await t.tap(find.text('Play again'));
    await t.pump();
    await t.pump();
    await t.pump();
    final i = audio.calls.indexOf('release');
    expect(audio.calls.sublist(i), ['release', 'stop', 'arm']);
  });

  testWidgets('the app going to the background during review releases the ring and closes the session', (t) async {
    await runAndStop(t);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await t.pump();
    await t.pump();
    expect(audio.calls, containsAllInOrder(['freeze', 'release', 'stop']));
    expect(audio.armed, isFalse);
    // a hidden app draws no frames: back in the foreground, the review has nothing left to play
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump();
    expect(find.text('Play the run'), findsNothing, reason: 'nothing is left to play');
  });

  testWidgets('the app going to the background during a run grades it and keeps nothing to replay', (t) async {
    await t.pumpWidget(screen());
    await t.tap(find.text('G major, 1 octave'));
    await t.pump();
    await t.pump();
    for (var i = 0; i < 4; i++) {
      engine.queuedNotes.add(n(g.notes[i].midi, 0, 2.0 + 0.5 * i));
    }
    await t.pump(const Duration(milliseconds: 150));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump();
    await t.pump();
    expect(find.text('Play again'), findsOneWidget);
    expect(audio.calls, containsAllInOrder(['arm', 'release', 'stop']));
    expect(find.text('Play the run'), findsNothing);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('closing the screen during review releases the ring', (t) async {
    await runAndStop(t);
    await t.pumpWidget(host(const SizedBox()));
    await t.pump();
    expect(audio.calls, containsAllInOrder(['release', 'stop']));
  });

  testWidgets('if the ring cannot be armed the run still works, with no replay, and capture closes at its end', (t) async {
    audio.armResult = false;
    await runAndStop(t);
    expect(find.text('Play again'), findsOneWidget);
    expect(find.text('Play the run'), findsNothing);
    expect(audio.started, isFalse);
  });
}
