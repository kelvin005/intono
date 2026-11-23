import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/meter_state.dart';

void main() {
  test('MIDI numbers are named with the octave, middle C is C4 and concert A is A4', () {
    expect(noteName(60), 'C4');
    expect(noteName(69), 'A4');
    expect(noteName(55), 'G3'); // the violin's open G string
    expect(noteName(76), 'E5'); // the open E string
    expect(noteName(61), 'C#4');
    expect(noteName(0), 'C-1');
  });

  test('the silent state shows no note', () {
    expect(MeterState.silent.voiced, isFalse);
    expect(MeterState.silent.label, '--');
  });

  test('a voiced state is labelled with the note and the signed cents', () {
    const s = MeterState(voiced: true, midiNote: 69, cents: 3.04, hz: 441.0, tSec: 1.0);
    expect(s.label, 'A4  +3.0');
    const t = MeterState(voiced: true, midiNote: 69, cents: -12.46, hz: 437.0, tSec: 1.0);
    expect(t.label, 'A4  -12.5');
    const z = MeterState(voiced: true, midiNote: 69, cents: 0.0, hz: 440.0, tSec: 1.0);
    expect(z.label, 'A4  +0.0');
  });
}
