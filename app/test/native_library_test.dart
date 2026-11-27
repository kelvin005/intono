import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/bench_runner.dart';
import 'package:intono_app/src/native_library.dart';

void main() {
  test('Android opens the shim library; iOS uses the process (statically linked, ADR 0010)', () {
    expect(nativeLibraryFor(BenchLibrary.product, ios: false), const NativeLibrary.file('libintono_android.so'));
    expect(nativeLibraryFor(BenchLibrary.noGuard, ios: false), const NativeLibrary.file('libintono_bench_noguard.so'));
    expect(nativeLibraryFor(BenchLibrary.product, ios: true), const NativeLibrary.process());
  });

  test('the guard-off comparison build does not exist on iOS', () {
    expect(nativeLibraryFor(BenchLibrary.noGuard, ios: true), isNull);
  });
}
