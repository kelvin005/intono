import 'package:intono_app/src/audio_control.dart';

class FakeAudio implements AudioControl {
  bool started = false;
  bool startResult = true;
  bool? drone;
  bool headphones = false;
  int pointer = 4242;
  String infoText = 'input: AAudio, Exclusive, 48000 Hz';
  String soakReport = 'soak (worker thread): 30.0 min';
  final soakCalls = <(int, bool)>[];
  int finishCalls = 0;

  // Replay (ADR 0013): every call in order, as 'arm', 'freeze', 'play 1.950-2.450', 'stop-playback', 'release', 'stop'.
  final calls = <String>[];
  bool armResult = true;
  bool armed = false;
  bool playing = false;

  @override
  Future<bool> start() async => started = startResult;

  @override
  Future<void> stop() async {
    calls.add('stop');
    started = false;
    armed = false;
    playing = false;
  }

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

  @override
  Future<bool> startSoak({required int minutes, required bool inlineEngine}) async {
    soakCalls.add((minutes, inlineEngine));
    return started = startResult;
  }

  @override
  Future<String> soakStatus() async => started ? '1.0 of 30.0 min: 60 s, queue high-water 3, dropped 0' : 'no soak running';

  @override
  Future<bool> replayArm({double seconds = 60}) async {
    calls.add('arm');
    return armed = started && armResult;
  }

  @override
  Future<void> replayFreeze() async => calls.add('freeze');

  @override
  Future<bool> replayPlay(double fromS, double toS) async {
    calls.add('play ${fromS.toStringAsFixed(3)}-${toS.toStringAsFixed(3)}');
    return playing = armed;
  }

  @override
  Future<void> replayStop() async {
    calls.add('stop-playback');
    playing = false;
  }

  @override
  Future<void> replayRelease() async {
    calls.add('release');
    armed = false;
    playing = false;
  }

  @override
  Future<bool> replayPlaying() async => playing;

  @override
  Future<String> finishSoak() async {
    finishCalls++;
    started = false;
    return soakReport;
  }
}
