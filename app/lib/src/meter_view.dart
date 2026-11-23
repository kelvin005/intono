import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'meter_state.dart';

/// How far from the target a note is, in display bands. These are display choices for the needle's colour, not DSP gates.
enum TuneZone {
  inTune,
  close,
  off;

  static TuneZone of(double cents) {
    final a = cents.abs();
    if (a <= 5) return TuneZone.inTune;
    if (a <= 15) return TuneZone.close;
    return TuneZone.off;
  }
}

const Color _green = Color(0xFF3DDC84);
const Color _amber = Color(0xFFFFC107);
const Color _red = Color(0xFFFF5252);
const Color _grey = Color(0xFF6B7885);

Color _zoneColor(TuneZone z) => switch (z) { TuneZone.inTune => _green, TuneZone.close => _amber, TuneZone.off => _red };

/// Note name, cents and a needle for one [MeterState]. Smoothing is done here, in the display (the DSP is not asked to smooth); with no
/// note the needle holds its last position, dimmed, instead of snapping to zero.
class MeterView extends StatefulWidget {
  const MeterView({super.key, required this.state});

  final MeterState state;

  @override
  State<MeterView> createState() => _MeterViewState();
}

class _MeterViewState extends State<MeterView> {
  double _heldCents = 0;

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    if (s.voiced) _heldCents = s.cents;
    final zone = TuneZone.of(_heldCents);
    return Semantics(
      container: true,
      label: s.semanticsLabel,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.noteLabel, style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w600, color: Color(0xFFE8ECEF), decoration: TextDecoration.none)),
          SizedBox(
            height: 32,
            child: Text(
              s.centsLabel,
              style: TextStyle(fontSize: 24, color: s.voiced ? _zoneColor(zone) : _grey, decoration: TextDecoration.none),
            ),
          ),
          const SizedBox(height: 8),
          AspectRatio(aspectRatio: 2, child: Needle(cents: _heldCents, active: s.voiced)),
        ],
      ),
    );
  }
}

/// The dial: a needle that eases to [cents] over a short time.
class Needle extends StatelessWidget {
  const Needle({super.key, required this.cents, required this.active});

  final double cents;
  final bool active;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(end: cents),
        duration: const Duration(milliseconds: 80),
        builder: (context, value, _) => CustomPaint(painter: NeedlePainter(cents: value, active: active), size: Size.infinite),
      );
}

class NeedlePainter extends CustomPainter {
  const NeedlePainter({required this.cents, required this.active});

  final double cents;
  final bool active;

  TuneZone get zone => TuneZone.of(cents);

  /// Radians from straight up: -50 to +50 cents map to -60 to +60 degrees; beyond that the needle pins at the end.
  static double angleFor(double cents) => cents.clamp(-50.0, 50.0) / 50.0 * (math.pi / 3);

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width / 2, size.height * 0.95);
    final r = math.min(size.width / 2, size.height * 0.9) * 0.95;
    final tick = Paint()
      ..color = _grey
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final c in const [-50.0, -25.0, 0.0, 25.0, 50.0]) {
      final a = angleFor(c);
      final dir = Offset(math.sin(a), -math.cos(a));
      final len = c == 0 ? 0.16 : 0.1;
      canvas.drawLine(pivot + dir * (r * (1 - len)), pivot + dir * r, tick);
    }
    final a = angleFor(cents);
    final color = active ? _zoneColor(zone) : _grey.withValues(alpha: 0.5);
    final needle = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pivot, pivot + Offset(math.sin(a), -math.cos(a)) * (r * 0.9), needle);
    canvas.drawCircle(pivot, 7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(NeedlePainter old) => old.cents != cents || old.active != active;
}
