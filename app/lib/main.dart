import 'dart:ffi';

import 'package:flutter/widgets.dart';

import 'src/audio_control.dart';
import 'src/bench_runner.dart';
import 'src/bench_screen.dart';
import 'src/debug_screen.dart';
import 'src/ffi/intono_bindings.dart';
import 'src/ffi_engine.dart';
import 'src/native_library.dart';

void main() {
  runApp(const IntonoApp());
}

class IntonoApp extends StatefulWidget {
  const IntonoApp({super.key});

  @override
  State<IntonoApp> createState() => _IntonoAppState();
}

class _IntonoAppState extends State<IntonoApp> {
  final AudioControl _audio = MethodChannelAudio();
  // Android: the shim library carries the whole C API (libintono linked statically, ADR 0009). iOS: libintono and the shim are linked
  // into the app, so the C API is in the process (ADR 0010). The platform side owns the engine either way.
  late final IntonoBindings _bindings = IntonoBindings(nativeLibraryFor(BenchLibrary.product)!.open());
  bool _bench = false;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _bench
            ? BenchScreen(
                audio: _audio,
                runner: const FfiBenchRunner(),
                engineFactory: (p) => FfiEngine(_bindings, Pointer<intono_engine>.fromAddress(p)),
                onClose: () => setState(() => _bench = false),
              )
            : DebugScreen(
                audio: _audio,
                engineFactory: (p) => FfiEngine(_bindings, Pointer<intono_engine>.fromAddress(p)),
                onOpenBench: () => setState(() => _bench = true),
              ),
      );
}
