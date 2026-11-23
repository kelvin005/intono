import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/audio_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('intono/audio');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'start':
          return true;
        case 'enginePointer':
          return 123456;
        case 'setDrone':
          return true;
        case 'info':
          return 'input: AAudio';
        case 'lastError':
          return '';
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  test('the method channel adapter speaks the protocol the Kotlin side implements', () async {
    final a = MethodChannelAudio();
    expect(await a.start(), isTrue);
    expect(await a.enginePointer(), 123456);
    expect(await a.setDrone(true, midiNote: 57, gain: 0.25), isTrue);
    expect(await a.info(), 'input: AAudio');
    expect(await a.lastError(), '');
    await a.stop();
    expect(calls.map((c) => c.method), ['start', 'enginePointer', 'setDrone', 'info', 'lastError', 'stop']);
    expect(calls[2].arguments, {'enabled': true, 'midiNote': 57, 'gain': 0.25});
  });

  test('a missing platform implementation reads as failure, not as a crash', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    final a = MethodChannelAudio();
    expect(await a.start(), isFalse);
    expect(await a.enginePointer(), 0);
    expect(await a.info(), 'unavailable');
  });
}
