import 'dart:ffi';

import 'package:flutter/widgets.dart';

import 'src/audio_control.dart';
import 'src/debug_screen.dart';
import 'src/ffi/intono_bindings.dart';
import 'src/ffi_engine.dart';

void main() {
  runApp(const IntonoApp());
}

class IntonoApp extends StatelessWidget {
  const IntonoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The shim library carries the whole C API (libintono linked statically, ADR 0009); the platform side owns the engine.
    final bindings = IntonoBindings(DynamicLibrary.open('libintono_android.so'));
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DebugScreen(
        audio: MethodChannelAudio(),
        engineFactory: (p) => FfiEngine(bindings, Pointer<intono_engine>.fromAddress(p)),
      ),
    );
  }
}
