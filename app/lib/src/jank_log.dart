/// UI frames that took longer than [thresholdUs] (build plus raster), with the time they started in CLOCK_MONOTONIC seconds, the same
/// clock the native shim stamps its slow hops with, so a slow hop can be matched to a UI frame by eye. Counts are for diagnosis only.
class JankLog {
  JankLog({this.thresholdUs = 20000, this.keep = 8});

  final int thresholdUs;
  final int keep;
  int count = 0;
  final List<({int startUs, int totalUs})> _recent = [];

  void add(int startUs, int totalUs) {
    if (totalUs <= thresholdUs) return;
    count++;
    _recent.add((startUs: startUs, totalUs: totalUs));
    if (_recent.length > keep) _recent.removeAt(0);
  }

  void clear() {
    count = 0;
    _recent.clear();
  }

  /// One line, or '' when there was no jank.
  String get text {
    if (count == 0) return '';
    final items = _recent.map((f) => '${(f.startUs / 1e6).toStringAsFixed(3)}:${(f.totalUs / 1000).toStringAsFixed(1)}').join(' ');
    return 'UI frames over ${thresholdUs ~/ 1000} ms: $count (t s, ms): $items';
  }
}
