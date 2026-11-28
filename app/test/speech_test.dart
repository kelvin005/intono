import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/engine_api.dart';
import 'package:intono_app/src/scales/grader.dart';
import 'package:intono_app/src/scales/grading_config.dart';
import 'package:intono_app/src/scales/scale.dart';
import 'package:intono_app/src/scales/scale_screen.dart';
import 'package:intono_app/src/settings_screen.dart';
import 'package:intono_app/src/speech.dart';

import 'fake_audio.dart';
import 'fake_engine.dart';

// The spoken summary (ADR 0017), written before it: after the run, with the microphone already off; stopped by replay and by leaving.

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

class FakeSpeech implements SpeechControl {
  FakeSpeech(this.log);
  final List<String> log;
  final spoken = <String>[];
  @override
  Future<bool> speak(String text) async {
    log.add('speak');
    spoken.add(text);
    return true;
  }

  @override
  Future<void> stop() async => log.add('stop-speech');
}

void main() {
  group('text and policy', () {
    test('the summary is the score, the counts and the tips, with cents and minus spoken', () {
      final notes = [for (var i = 0; i < 3; i++) n(g.notes[i].midi, [1.0, 8.0, -20.0][i], 0.5 * i)];
      final r = gradeScale(g, notes, const GradingConfig());
      final s = spokenSummary(r, ['Your open D string is often 10¢ flat. Tune it against the drone before you play.', 'average −2¢']);
      expect(s, 'Score ${r.scorePercent.round()} percent. 1 green, 1 yellow, 1 red, 12 missed. '
          'Your open D string is often 10 cents flat. Tune it against the drone before you play. average minus 2 cents');
    });

    test('auto speaks only with headphones; on and off are what they say', () {
      expect(shouldSpeak(SpokenMode.auto, headphones: true), isTrue);
      expect(shouldSpeak(SpokenMode.auto, headphones: false), isFalse);
      expect(shouldSpeak(SpokenMode.on, headphones: false), isTrue);
      expect(shouldSpeak(SpokenMode.off, headphones: true), isFalse);
      expect(SpokenMode.parse(null), SpokenMode.auto);
      expect(SpokenMode.parse('on'), SpokenMode.on);
      expect(SpokenMode.parse('nonsense'), SpokenMode.auto);
      expect(SpokenMode.auto.next, SpokenMode.on);
      expect(SpokenMode.on.next, SpokenMode.off);
      expect(SpokenMode.off.next, SpokenMode.auto);
    });
  });

  group('on the review screen', () {
    late FakeAudio audio;
    late FakeEngine engine;
    late FakeSpeech speech;
    var speak = true;
    Widget screen() => host(ScaleScreen(
          audio: audio,
          engineFactory: (_) => engine,
          library: lib,
          config: const GradingConfig(),
          onClose: () {},
          coach: (r) async => ['Tip one.'],
          speech: speech,
          speakSummary: () async => speak,
        ));

    setUp(() {
      audio = FakeAudio();
      engine = FakeEngine();
      speech = FakeSpeech(audio.calls);
      speak = true;
    });

    Future<void> runAndStop(WidgetTester t) async {
      await t.pumpWidget(screen());
      await t.tap(find.text('G major, 1 octave'));
      await t.pump();
      await t.pump();
      engine.queuedNotes.add(n(55, 0, 2.0));
      await t.pump(const Duration(milliseconds: 150));
      await t.tap(find.text('Stop'));
      await t.pump();
      await t.pump();
    }

    testWidgets('it speaks once, after capture has ended (the microphone is off)', (t) async {
      await runAndStop(t);
      expect(speech.spoken.single, endsWith('Tip one.'));
      expect(audio.calls.indexOf('speak'), greaterThan(audio.calls.indexOf('freeze')));
    });

    testWidgets('it does not speak when the policy says no', (t) async {
      speak = false;
      await runAndStop(t);
      expect(speech.spoken, isEmpty);
    });

    testWidgets('a replay stops the speech first', (t) async {
      await runAndStop(t);
      await t.tap(find.text('Play the run'));
      await t.pump();
      final i = audio.calls.lastIndexOf('stop-speech');
      expect(i, greaterThan(0));
      expect(audio.calls[i + 1], startsWith('play '));
    });

    testWidgets('leaving the review stops the speech', (t) async {
      await runAndStop(t);
      await t.tap(find.text('Scales'));
      await t.pump();
      await t.pump();
      expect(audio.calls, containsAllInOrder(['speak', 'stop-speech', 'release', 'stop']));
    });

    testWidgets('the app going to the background stops the speech', (t) async {
      await runAndStop(t);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await t.pump();
      expect(audio.calls.sublist(audio.calls.indexOf('speak')), contains('stop-speech'));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('closing the screen stops the speech', (t) async {
      await runAndStop(t);
      await t.pumpWidget(host(const SizedBox()));
      await t.pump();
      expect(audio.calls.sublist(audio.calls.indexOf('speak')), contains('stop-speech'));
    });
  });

  testWidgets('Settings cycles the spoken summary: auto, on, off', (t) async {
    final changes = <SpokenMode>[];
    var mode = SpokenMode.auto;
    await t.pumpWidget(host(StatefulBuilder(
        builder: (ctx, set) => SettingsScreen(
              onClearHistory: () async {},
              onClose: () {},
              spokenMode: mode,
              onSpokenModeChanged: (m) => set(() {
                changes.add(m);
                mode = m;
              }),
            ))));
    expect(find.text('Spoken summary: with headphones'), findsOneWidget);
    await t.tap(find.text('Spoken summary: with headphones'));
    await t.pump();
    expect(find.text('Spoken summary: on'), findsOneWidget);
    await t.tap(find.text('Spoken summary: on'));
    await t.pump();
    expect(find.text('Spoken summary: off'), findsOneWidget);
    expect(changes, [SpokenMode.on, SpokenMode.off]);
  });
}
