import 'dart:ffi';
import 'dart:io' show Platform;

import 'bench_runner.dart';

/// Where the C API lives: a shared library on Android (libintono_android.so, ADR 0009), the process itself on iOS, where libintono and
/// the shim are linked statically into the app (ADR 0010).
class NativeLibrary {
  const NativeLibrary.file(this.fileName);
  const NativeLibrary.process() : fileName = null;

  final String? fileName;

  DynamicLibrary open() => fileName == null ? DynamicLibrary.process() : DynamicLibrary.open(fileName!);

  @override
  bool operator ==(Object other) => other is NativeLibrary && other.fileName == fileName;

  @override
  int get hashCode => fileName.hashCode;

  @override
  String toString() => fileName == null ? 'NativeLibrary.process()' : 'NativeLibrary.file($fileName)';
}

/// The library for [lib] on this platform, or null if that build is not shipped there (the guard-off comparison is Android-only).
NativeLibrary? nativeLibraryFor(BenchLibrary lib, {bool? ios}) {
  final onIos = ios ?? Platform.isIOS;
  if (onIos) return lib == BenchLibrary.product ? const NativeLibrary.process() : null;
  return NativeLibrary.file(lib.fileName);
}
