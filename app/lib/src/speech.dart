import 'package:flutter/services.dart';

import 'scales/grader.dart';

/// The phone's own text-to-speech (ADR 0017): Android TextToSpeech, iOS AVSpeechSynthesizer, through the `intono/speech` channel.
abstract class SpeechControl {
  /// Starts speaking [text] (replacing anything being spoken). False if the engine could not start.
  Future<bool> speak(String text);

  Future<void> stop();
}

class MethodChannelSpeech implements SpeechControl {
  MethodChannelSpeech([MethodChannel? channel]) : _ch = channel ?? const MethodChannel('intono/speech');
  final MethodChannel _ch;

  @override
  Future<bool> speak(String text) async {
    try {
      return await _ch.invokeMethod<bool>('speak', {'text': text}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _ch.invokeMethod<void>('stopSpeaking');
    } on PlatformException {
      // nothing was speaking
    } on MissingPluginException {
      // no speech on this platform
    }
  }
}

/// The `spoken_summary` setting (ADR 0017): auto (only with headphones, the default), on, off.
enum SpokenMode {
  auto,
  on,
  off;

  static const settingKey = 'spoken_summary';

  static SpokenMode parse(String? v) => switch (v) { 'on' => on, 'off' => off, _ => auto };

  SpokenMode get next => switch (this) { auto => on, on => off, off => auto };

  String get label => switch (this) { auto => 'with headphones', on => 'on', off => 'off' };
}

bool shouldSpeak(SpokenMode mode, {required bool headphones}) => switch (mode) {
      SpokenMode.on => true,
      SpokenMode.off => false,
      SpokenMode.auto => headphones,
    };

/// One utterance: the score and counts, then the tips, with "¢" and the minus sign made speakable.
String spokenSummary(ScaleResult r, List<String> tips) {
  final head = 'Score ${r.scorePercent.round()} percent. ${r.green} green, ${r.yellow} yellow, ${r.red} red, ${r.missed} missed.';
  return [head, ...tips].join(' ').replaceAll('−', 'minus ').replaceAll('¢', ' cents');
}
