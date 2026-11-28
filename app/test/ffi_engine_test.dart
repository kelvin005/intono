// The real thing over dart:ffi, on the host: set INTONO_LIB to a libintono shared library (CI builds one from dsp/). It proves the struct
// layouts ffigen produced match the C compiler's, and that the polling path reads real frames. Skipped when INTONO_LIB is not set.
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intono_app/src/ffi/intono_bindings.dart';
import 'package:intono_app/src/ffi_engine.dart';

void main() {
  final path = Platform.environment['INTONO_LIB'];
  final skip = path == null ? 'INTONO_LIB is not set' : false;

  test('struct sizes match the C layout', skip: skip, () {
    // intono_frame: double + 2 floats + int + float + 2 floats + 2 ints = 8 + 8 + 4 + 4 + 8 + 8 = 40 bytes, 8-aligned.
    expect(sizeOf<intono_frame>(), 40);
    // intono_note: 2 doubles + int + 5 floats + int = 16 + 4 + 20 + 4 = 44, padded to 48.
    expect(sizeOf<intono_note>(), 48);
    expect(sizeOf<intono_config>(), 28);
  });

  test('a 440 Hz tone read through FfiEngine is A4, voiced, in tune', skip: skip, () {
    final lib = IntonoBindings(DynamicLibrary.open(path!));
    final cfg = calloc<intono_config>();
    cfg.ref
      ..sample_rate = 48000
      ..window_size = 1024
      ..hop_size = 256
      ..a4_hz = 440
      ..tuning = 0
      ..min_hz = 180
      ..max_hz = 3200;
    final engine = lib.intono_create(cfg);
    calloc.free(cfg);
    expect(engine.address, isNot(0));

    const n = 24000;
    final buf = calloc<Float>(n);
    for (var i = 0; i < n; i++) {
      buf[i] = 0.4 * math.sin(2 * math.pi * 440.0 * i / 48000.0);
    }
    lib.intono_process(engine, buf, n);
    calloc.free(buf);

    final api = FfiEngine(lib, engine);
    var last = api.readFrames();
    var total = last;
    var newest = last > 0 ? api.frameAt(last - 1) : null;
    while (last == api.frameCapacity) {
      last = api.readFrames();
      total += last;
      if (last > 0) newest = api.frameAt(last - 1);
    }
    expect(total, greaterThan(50));
    expect(newest, isNotNull);
    expect(newest!.isVoiced, isTrue);
    expect(newest.midiNote, 69);
    expect(newest.cents.abs(), lessThan(5));
    expect(newest.hz, closeTo(440, 3));
    api.dispose();
    lib.intono_destroy(engine);
  });

  test('setExpected reaches the real engine and a scale played as expected comes back note for note (ADR 0014)', skip: skip, () {
    final lib = IntonoBindings(DynamicLibrary.open(path!));
    final cfg = calloc<intono_config>();
    cfg.ref
      ..sample_rate = 48000
      ..window_size = 1024
      ..hop_size = 256
      ..a4_hz = 440
      ..tuning = 0
      ..min_hz = 180
      ..max_hz = 3200;
    final engine = lib.intono_create(cfg);
    calloc.free(cfg);
    final api = FfiEngine(lib, engine);
    const scale = [67, 69, 71, 72];
    api.setExpected(scale);
    const per = 12000; // 250 ms per note, then 1 s of silence closes the last one
    const n = per * 4 + 48000;
    final buf = calloc<Float>(n);
    var ph = 0.0;
    for (var i = 0; i < n; i++) {
      final k = i ~/ per;
      if (k < 4) {
        final hz = 440.0 * math.pow(2, (scale[k] - 69) / 12);
        ph += 2 * math.pi * hz / 48000.0;
        var x = 0.0;
        for (var h = 1; h <= 8; h++) {
          x += 0.3 / h * math.sin(h * ph);
        }
        buf[i] = x;
      }
    }
    for (var p = 0; p < n; p += 256) {
      lib.intono_process(engine, buf + p, math.min(256, n - p));
    }
    calloc.free(buf);
    // The engine decodes notes on its worker thread (ADR 0008), so the last note can come out after the last block was processed:
    // keep reading until all are there or 2 s have passed (it failed once on a slow runner reading only once, #46).
    final got = <int>[];
    for (var tries = 0; tries < 200 && got.length < scale.length; tries++) {
      final k = api.readNotes();
      for (var i = 0; i < k; i++) {
        got.add(api.noteAt(i).midiNote);
      }
      if (got.length < scale.length) sleep(const Duration(milliseconds: 10));
    }
    expect(got, scale);
    api.setExpected(const []); // back to free mode
    api.dispose();
    api.setExpected(scale); // after dispose: a no-op, not a crash
    lib.intono_destroy(engine);
  });
}
