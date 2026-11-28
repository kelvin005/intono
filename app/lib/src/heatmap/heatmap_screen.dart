import 'package:flutter/widgets.dart';

import '../scales/grading_config.dart';
import '../scales/scale_screen.dart' show ScaleColors;
import '../ui_button.dart';
import 'heatmap.dart';

/// The finger-level heatmap (architecture doc, "Coaching"; data: `graded_notes` of the last 30 days). Columns are the strings G D A E,
/// rows the fingers (and low/high placements) that occur. A cell shows the average cents error, coloured by the grader's thresholds on
/// its mean absolute error; tapping it shows the sentence ("A string, 3rd finger (high): average +15¢ over 12 notes in 4 sessions").
class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key, required this.load, required this.config, required this.onClose});

  final Future<List<HeatCell>> Function() load;
  final GradingConfig config;
  final VoidCallback onClose;

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  List<HeatCell>? _cells;
  String _error = '';
  HeatCell? _selected;

  @override
  void initState() {
    super.initState();
    widget.load().then((c) {
      if (mounted) setState(() => _cells = c);
    }, onError: (Object _) {
      if (mounted) setState(() => _error = 'The heatmap could not be loaded.');
    });
  }

  static const _strings = ['G', 'D', 'A', 'E'];

  String _rowLabel(int finger, String? placement) =>
      finger == 0 ? 'Open' : '${ordinal(finger)}${placement == null ? '' : ' $placement'}';

  Widget _grid(List<HeatCell> cells) {
    final rows = <(int, String?)>[];
    for (final c in cells) {
      final r = (c.finger, c.placement);
      if (!rows.contains(r)) rows.add(r);
    }
    rows.sort((a, b) {
      final f = a.$1.compareTo(b.$1);
      if (f != 0) return f;
      int p(String? x) => switch (x) { 'low' => 0, null => 1, _ => 2 };
      return p(a.$2).compareTo(p(b.$2));
    });
    HeatCell? at(String s, int f, String? p) {
      for (final c in cells) {
        if (c.string == s && c.finger == f && c.placement == p) return c;
      }
      return null;
    }

    Widget cell(String s, (int, String?) r) {
      final c = at(s, r.$1, r.$2);
      final box = Container(
        height: 44,
        margin: const EdgeInsets.all(2),
        alignment: Alignment.center,
        color: c == null ? const Color(0xFF1A1F24) : ScaleColors.of(c.grade(widget.config)),
        child: Text(c == null ? '' : (c.meanCents == null ? 'missed' : signedCents(c.meanCents!)),
            style: const TextStyle(fontSize: 13)),
      );
      if (c == null) return Expanded(child: box);
      return Expanded(
        child: GestureDetector(
          key: ValueKey('heat:${c.string}:${c.finger}:${c.placement ?? ''}'),
          onTap: () => setState(() => _selected = c),
          child: box,
        ),
      );
    }

    return Column(children: [
      Row(children: [
        const SizedBox(width: 64),
        for (final s in _strings) Expanded(child: Center(child: Text(s, style: const TextStyle(fontSize: 16)))),
      ]),
      for (final r in rows)
        Row(children: [
          SizedBox(width: 64, child: Text(_rowLabel(r.$1, r.$2), style: const TextStyle(fontSize: 13))),
          for (final s in _strings) cell(s, r),
        ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cells = _cells;
    return DefaultTextStyle(
      style: const TextStyle(color: Color(0xFFE8ECEF), fontSize: 16, decoration: TextDecoration.none),
      child: ColoredBox(
        color: const Color(0xFF101418),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppButton(label: 'Back', onTap: widget.onClose),
              const SizedBox(height: 12),
              const Text('Heatmap', style: TextStyle(fontSize: 22)),
              const Text('Last 30 days', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              if (_error.isNotEmpty) Text(_error),
              if (_error.isEmpty && cells == null) const Text('Loading…'),
              if (cells != null && cells.isEmpty) const Text('No graded notes in the last 30 days yet. Play a scale first.'),
              if (cells != null && cells.isNotEmpty) ...[
                _grid(cells),
                const SizedBox(height: 16),
                Text(_selected?.describe() ?? 'Tap a cell for details.'),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
