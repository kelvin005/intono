import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/meter_state.dart';
import 'package:intono_app/src/meter_view.dart';

Widget host(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(data: const MediaQueryData(), child: Center(child: SizedBox(width: 320, height: 320, child: child))),
    );

MeterState voiced(int midi, double cents) => MeterState(voiced: true, midiNote: midi, cents: cents, hz: 440, tSec: 1);

NeedlePainter painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.descendant(of: find.byType(Needle), matching: find.byType(CustomPaint)).first).painter! as NeedlePainter;

void main() {
  group('needle geometry and zones (display choices, not DSP gates)', () {
    test('0 cents is straight up; the range is +-50 cents over +-60 degrees; beyond it the needle pins', () {
      expect(NeedlePainter.angleFor(0), 0);
      expect(NeedlePainter.angleFor(50), closeTo(math.pi / 3, 1e-12));
      expect(NeedlePainter.angleFor(-50), closeTo(-math.pi / 3, 1e-12));
      expect(NeedlePainter.angleFor(25), closeTo(math.pi / 6, 1e-12));
      expect(NeedlePainter.angleFor(80), closeTo(math.pi / 3, 1e-12));
      expect(NeedlePainter.angleFor(-400), closeTo(-math.pi / 3, 1e-12));
    });

    test('zones: within 5 cents is in tune, within 15 is close, otherwise off', () {
      expect(TuneZone.of(0), TuneZone.inTune);
      expect(TuneZone.of(-5), TuneZone.inTune);
      expect(TuneZone.of(5.01), TuneZone.close);
      expect(TuneZone.of(-15), TuneZone.close);
      expect(TuneZone.of(15.01), TuneZone.off);
      expect(TuneZone.of(-49), TuneZone.off);
    });
  });

  group('MeterState text', () {
    test('note name, cents text and the spoken description', () {
      final s = voiced(69, 3.04);
      expect(s.noteLabel, 'A4');
      expect(s.centsLabel, '+3.0');
      expect(s.semanticsLabel, 'A4, 3.0 cents sharp');
      expect(voiced(61, -12.46).centsLabel, '-12.5');
      expect(voiced(61, -12.46).semanticsLabel, 'C#4, 12.5 cents flat');
      expect(voiced(69, 0.02).semanticsLabel, 'A4, in tune');
      expect(voiced(69, -0.02).centsLabel, '+0.0');
      expect(MeterState.silent.noteLabel, '--');
      expect(MeterState.silent.centsLabel, '');
      expect(MeterState.silent.semanticsLabel, 'No note');
    });
  });

  group('MeterView', () {
    testWidgets('shows the note, the cents, and a needle at the cents', (tester) async {
      await tester.pumpWidget(host(MeterView(state: voiced(69, 3.04))));
      await tester.pumpAndSettle();
      expect(find.text('A4'), findsOneWidget);
      expect(find.text('+3.0'), findsOneWidget);
      expect(painter(tester).cents, closeTo(3.04, 1e-9));
      expect(painter(tester).active, isTrue);
      expect(painter(tester).zone, TuneZone.inTune);
    });

    testWidgets('the needle moves smoothly: partway after a moment, at the target after it settles', (tester) async {
      await tester.pumpWidget(host(MeterView(state: voiced(69, 0))));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(MeterView(state: voiced(69, 40))));
      await tester.pump(const Duration(milliseconds: 30));
      final mid = painter(tester).cents;
      expect(mid, greaterThan(0));
      expect(mid, lessThan(40));
      await tester.pumpAndSettle();
      expect(painter(tester).cents, closeTo(40, 1e-9));
      expect(painter(tester).zone, TuneZone.off);
    });

    testWidgets('with no note the text clears and the needle holds its last position, dimmed', (tester) async {
      await tester.pumpWidget(host(MeterView(state: voiced(69, 20))));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(const MeterView(state: MeterState.silent)));
      await tester.pumpAndSettle();
      expect(find.text('--'), findsOneWidget);
      expect(find.text('+20.0'), findsNothing);
      expect(painter(tester).cents, closeTo(20, 1e-9));
      expect(painter(tester).active, isFalse);
    });

    testWidgets('exposes one spoken description instead of the pieces', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(MeterView(state: voiced(69, -3.04))));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('A4, 3.0 cents flat'), findsOneWidget);
      handle.dispose();
    });
  });
}
