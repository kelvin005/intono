/// What the meter shows: the newest frame's note and cents, or nothing when the engine hears no instrument.
class MeterState {
  const MeterState({required this.voiced, required this.midiNote, required this.cents, required this.hz, required this.tSec});

  static const MeterState silent = MeterState(voiced: false, midiNote: 0, cents: 0, hz: 0, tSec: 0);

  final bool voiced;
  final int midiNote;
  final double cents; // against the target of the configured tuning
  final double hz; // the displayed pitch (vibrato centre)
  final double tSec;

  /// "A4", or "--" when unvoiced.
  String get noteLabel => voiced ? noteName(midiNote) : '--';

  /// "+3.0" / "-12.5" (one decimal, always signed), or "" when unvoiced.
  String get centsLabel {
    if (!voiced) return '';
    var c = cents.toStringAsFixed(1);
    if (c == '-0.0') c = '0.0';
    return c.startsWith('-') ? c : '+$c';
  }

  /// "A4  +3.0", or "--" when unvoiced.
  String get label => voiced ? '$noteLabel  $centsLabel' : '--';

  /// What a screen reader says for the whole meter.
  String get semanticsLabel {
    if (!voiced) return 'No note';
    final c = cents.toStringAsFixed(1);
    if (c == '0.0' || c == '-0.0') return '$noteLabel, in tune';
    final mag = cents.abs().toStringAsFixed(1);
    return '$noteLabel, $mag cents ${cents > 0 ? 'sharp' : 'flat'}';
  }
}

const List<String> _names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

/// MIDI note number to scientific pitch name: 60 is C4, 69 is A4.
String noteName(int midi) => '${_names[midi % 12]}${midi ~/ 12 - 1}';
