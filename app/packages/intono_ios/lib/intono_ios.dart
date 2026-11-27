/// Intono's iOS platform side (ADR 0010). It has no Dart API: the app talks to it over the method channel `intono/audio`
/// (`AudioControl`), as it talks to the Kotlin side on Android, and reads the engine over dart:ffi with `DynamicLibrary.process()`.
library;
