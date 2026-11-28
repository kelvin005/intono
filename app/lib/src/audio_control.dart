import 'package:flutter/services.dart';

/// The platform side of audio: permission, the Oboe streams, the engine's lifetime (ADR 0009: Kotlin glue, no audio crosses it).
abstract class AudioControl {
  /// Asks for the microphone permission if needed, opens the streams and creates the engine. False on failure ([lastError] says why).
  Future<bool> start();

  /// Stops the streams and destroys the engine. Pointers from [enginePointer] are invalid afterwards.
  Future<void> stop();

  /// The engine's address for dart:ffi; 0 when stopped.
  Future<int> enginePointer();

  Future<bool> setDrone(bool on, {int midiNote = 57, double gain = 0.3});

  /// Whether the audio output is headphone-like (wired, USB, Bluetooth).
  Future<bool> headphonesConnected();

  /// Granted stream modes, sample rate, buffer sizes, hop timings: text only, never audio.
  Future<String> info();

  Future<String> lastError();

  /// Bench-mode soak (ADR 0008 W3/W4, polling power cost): capture with the worker latency probe armed for [minutes]; [inlineEngine]
  /// runs without the worker thread (the battery baseline). The screen stays on until [finishSoak] or [stop].
  Future<bool> startSoak({required int minutes, required bool inlineEngine});

  /// One progress line (elapsed, queue high-water so far, drops so far).
  Future<String> soakStatus();

  /// Stops capture and returns the soak report (numbers and stream facts, never audio). The engine pointer is invalid afterwards.
  Future<String> finishSoak();

  // Replay (ADR 0013). The audio stays in the shim's RAM ring: it never crosses to Dart, is never written to disk and never uploaded.

  /// Starts keeping the last [seconds] of input in RAM (a scale run). Releases any previous run first. False if it cannot.
  Future<bool> replayArm({double seconds = 60});

  /// The run is over: the microphone no longer reaches the engine or the ring (nothing grades the playback); the session stays open
  /// for playback.
  Future<void> replayFreeze();

  /// Plays the kept audio from [fromS] to [toS] in the engine's time (seconds, as in a note's tStart and tEnd). False if none of it is
  /// kept.
  Future<bool> replayPlay(double fromS, double toS);

  Future<void> replayStop();

  /// Stops playback, zeroes the ring and frees it. Call before [stop] when a review ends.
  Future<void> replayRelease();

  Future<bool> replayPlaying();
}

class MethodChannelAudio implements AudioControl {
  MethodChannelAudio([MethodChannel? channel]) : _ch = channel ?? const MethodChannel('intono/audio');

  final MethodChannel _ch;

  Future<T> _call<T>(String method, T fallback, [Object? args]) async {
    try {
      final r = await _ch.invokeMethod<T>(method, args);
      return r ?? fallback;
    } on MissingPluginException {
      return fallback;
    } on PlatformException {
      return fallback;
    }
  }

  @override
  Future<bool> start() => _call<bool>('start', false);

  @override
  Future<void> stop() => _call<Object?>('stop', null);

  @override
  Future<int> enginePointer() => _call<int>('enginePointer', 0);

  @override
  Future<bool> setDrone(bool on, {int midiNote = 57, double gain = 0.3}) =>
      _call<bool>('setDrone', false, {'enabled': on, 'midiNote': midiNote, 'gain': gain});

  @override
  Future<bool> headphonesConnected() => _call<bool>('headphones', false);

  @override
  Future<String> info() => _call<String>('info', 'unavailable');

  @override
  Future<String> lastError() => _call<String>('lastError', '');

  @override
  Future<bool> startSoak({required int minutes, required bool inlineEngine}) =>
      _call<bool>('startSoak', false, {'minutes': minutes, 'inline': inlineEngine});

  @override
  Future<String> soakStatus() => _call<String>('soakStatus', 'unavailable');

  @override
  Future<String> finishSoak() => _call<String>('finishSoak', 'soak report unavailable');

  @override
  Future<bool> replayArm({double seconds = 60}) => _call<bool>('replayArm', false, {'seconds': seconds});

  @override
  Future<void> replayFreeze() => _call<Object?>('replayFreeze', null);

  @override
  Future<bool> replayPlay(double fromS, double toS) => _call<bool>('replayPlay', false, {'from': fromS, 'to': toS});

  @override
  Future<void> replayStop() => _call<Object?>('replayStop', null);

  @override
  Future<void> replayRelease() => _call<Object?>('replayRelease', null);

  @override
  Future<bool> replayPlaying() => _call<bool>('replayPlaying', false);
}
