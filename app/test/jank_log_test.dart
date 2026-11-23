import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/jank_log.dart';

void main() {
  test('only frames over the threshold are kept; everything is counted', () {
    final j = JankLog(thresholdUs: 20000);
    j.add(1000000, 16000);
    j.add(2000000, 20000); // not over: exclusive
    expect(j.count, 0);
    expect(j.text, '');
    j.add(3000000, 34200);
    expect(j.count, 1);
    expect(j.text, 'UI frames over 20 ms: 1 (t s, ms): 3.000:34.2');
  });

  test('the list keeps the newest eight while the count keeps all', () {
    final j = JankLog(thresholdUs: 20000);
    for (var i = 0; i < 12; i++) {
      j.add(1000000 * (i + 1), 25000 + i * 1000);
    }
    expect(j.count, 12);
    expect(j.text, startsWith('UI frames over 20 ms: 12 (t s, ms): 5.000:29.0'));
    expect(j.text, endsWith('12.000:36.0'));
    expect(j.text.split(' ').where((p) => p.contains(':') && p.contains('.')).length, 8);
  });

  test('clear forgets everything', () {
    final j = JankLog()..add(1000000, 50000);
    j.clear();
    expect(j.count, 0);
    expect(j.text, '');
  });
}
