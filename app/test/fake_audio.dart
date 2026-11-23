import 'package:intono_app/src/audio_control.dart';

class FakeAudio implements AudioControl {
  bool started = false;
  bool startResult = true;
  bool? drone;
  bool headphones = false;
  int pointer = 4242;
  String infoText = 'input: AAudio, Exclusive, 48000 Hz';

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
  Future<bool> headphonesConnected() async => headphones;

  @override
  Future<String> info() async => started ? infoText : 'stopped';

  @override
  Future<String> lastError() async => started ? '' : 'no microphone permission';
}
