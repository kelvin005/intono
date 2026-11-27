import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'native_library.dart';

enum BenchLibrary {
  /// The shim's own engine (denormal guard ON, the product build).
  product('libintono_android.so'),

  /// The comparison build (guard OFF), present only in the bench APK (ADR 0009 answer 4).
  noGuard('libintono_bench_noguard.so');

  const BenchLibrary(this.fileName);
  final String fileName;
}

/// Runs the native worst-hop bench (generated signal, timings only) in one of the two builds.
abstract class BenchRunner {
  /// The report text, or null if that library is not in this APK.
  Future<String?> run(BenchLibrary lib, int runs);
}

class FfiBenchRunner implements BenchRunner {
  const FfiBenchRunner();

  /// In a separate isolate: the bench takes seconds and must not block the UI isolate (nor share its thread's timing).
  @override
  Future<String?> run(BenchLibrary lib, int runs) => Isolate.run(() => _runHere(lib, runs));
}

typedef _BenchNative = Int32 Function(Int32, Pointer<Utf8>, Int32);
typedef _BenchDart = int Function(int, Pointer<Utf8>, int);

String? _runHere(BenchLibrary which, int runs) {
  final where = nativeLibraryFor(which);
  if (where == null) return null;
  final DynamicLibrary lib;
  final _BenchDart fn;
  try {
    lib = where.open();
    fn = lib.lookupFunction<_BenchNative, _BenchDart>('intono_bench_run');
  } on ArgumentError {
    return null;
  }
  const cap = 4096;
  final buf = calloc<Uint8>(cap).cast<Utf8>();
  try {
    final n = fn(runs, buf, cap);
    return n > 0 ? buf.toDartString() : null;
  } finally {
    calloc.free(buf);
  }
}
