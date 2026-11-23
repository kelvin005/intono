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
}
