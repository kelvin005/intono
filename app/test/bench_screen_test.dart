import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/bench_runner.dart';
import 'package:intono_app/src/bench_screen.dart';

import 'fake_audio.dart';

class FakeRunner implements BenchRunner {
  final calls = <(BenchLibrary, int)>[];
  String? noGuard = 'bench (guard OFF): 10 runs x 2437 hops';
  String product = 'bench (guard ON): 10 runs x 2437 hops';
  @override
  Future<String?> run(BenchLibrary lib, int runs) async {
    calls.add((lib, runs));
    return lib == BenchLibrary.product ? product : noGuard;
  }
}

Widget host(Widget child) => Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  testWidgets('Run measures both builds, then captures the stream facts for the configured time, and shows one report', (tester) async {
    final audio = FakeAudio()..infoText = 'input: AAudio, Shared, latency 23.0 ms\nhop us: median 147.5';
    final runner = FakeRunner();
    await tester.pumpWidget(host(BenchScreen(audio: audio, runner: runner, onClose: () {}, captureSeconds: 10)));
    expect(find.text('Run'), findsOneWidget);

    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump();
    expect(runner.calls, [(BenchLibrary.product, 10), (BenchLibrary.noGuard, 10)]);
    expect(audio.started, isTrue, reason: 'the capture phase is running');
    expect(find.textContaining('guard ON'), findsNothing, reason: 'the report appears when everything is done');

    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    await tester.pump();
    expect(audio.started, isFalse);
    final text = tester.widget<Text>(find.byKey(const Key('bench-report'))).data!;
    expect(text.indexOf('guard ON'), lessThan(text.indexOf('guard OFF')));
    expect(text.indexOf('guard OFF'), lessThan(text.indexOf('latency 23.0 ms')));
    expect(text, contains('capture 10 s'));
    expect(text, contains('hop us: median 147.5'));
  });

  testWidgets('a build without the comparison library says so, and a failed capture start says why', (tester) async {
    final audio = FakeAudio()..startResult = false;
    final runner = FakeRunner()..noGuard = null;
    await tester.pumpWidget(host(BenchScreen(audio: audio, runner: runner, onClose: () {}, captureSeconds: 10)));
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    final text = tester.widget<Text>(find.byKey(const Key('bench-report'))).data!;
    expect(text, contains('guard ON'));
    expect(text, contains('comparison build (guard OFF): not in this APK'));
    expect(text, contains('capture: could not start: no microphone permission'));
  });

  testWidgets('Copy puts the whole report on the clipboard', (tester) async {
    final clip = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clip.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final audio = FakeAudio();
    await tester.pumpWidget(host(BenchScreen(audio: audio, runner: FakeRunner(), onClose: () {}, captureSeconds: 1)));
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    final shown = tester.widget<Text>(find.byKey(const Key('bench-report'))).data!;
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(clip, [shown]);
  });

  testWidgets('a second tap while running is ignored; Back closes', (tester) async {
    final audio = FakeAudio();
    final runner = FakeRunner();
    var closed = 0;
    await tester.pumpWidget(host(BenchScreen(audio: audio, runner: runner, onClose: () => closed++, captureSeconds: 5)));
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.tap(find.text('Running...'));
    await tester.pump();
    await tester.pump();
    expect(runner.calls.length, 2, reason: 'one run, not two');
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Back'));
    expect(closed, 1);
  });
}
