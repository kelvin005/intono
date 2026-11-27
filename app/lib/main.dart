import 'dart:ffi';

import 'package:flutter/widgets.dart';

import 'src/audio_control.dart';
import 'src/bench_runner.dart';
import 'src/bench_screen.dart';
import 'src/debug_screen.dart';
import 'src/ffi/intono_bindings.dart';
import 'src/ffi_engine.dart';

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
  // The shim library carries the whole C API (libintono linked statically, ADR 0009); the platform side owns the engine.
  late final IntonoBindings _bindings = IntonoBindings(DynamicLibrary.open('libintono_android.so'));
  bool _bench = false;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _bench
            ? BenchScreen(audio: _audio, runner: const FfiBenchRunner(), onClose: () => setState(() => _bench = false))
            : DebugScreen(
                audio: _audio,
                engineFactory: (p) => FfiEngine(_bindings, Pointer<intono_engine>.fromAddress(p)),
                onOpenBench: () => setState(() => _bench = true),
              ),
      );
}
