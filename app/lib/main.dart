import 'dart:ffi';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import 'src/audio_control.dart';
import 'src/bench_runner.dart';
import 'src/bench_screen.dart';
import 'src/db/practice_db_open.dart';
import 'src/coaching/coaching.dart';
import 'src/db/practice_stats.dart';
import 'src/db/practice_store.dart';
import 'src/heatmap/heatmap.dart';
import 'src/heatmap/heatmap_screen.dart';
import 'src/debug_screen.dart';
import 'src/ffi/intono_bindings.dart';
import 'src/ffi_engine.dart';
import 'src/native_library.dart';
import 'src/scales/grading_config.dart';
import 'src/scales/scale.dart';
import 'src/scales/scale_screen.dart';
import 'src/settings_screen.dart';

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
  bool _scales = false;
  bool _settings = false;
  bool _heatmap = false;
  PracticeStore? _store; // the practice history (ADR 0015); null until opened, or if it cannot be opened
  ScaleLibrary? _library;
  GradingConfig _grading = const GradingConfig();
  CoachingConfig _coaching = const CoachingConfig();

  @override
  void initState() {
    super.initState();
    _loadScaleAssets();
    _openStore();
  }

  Future<void> _openStore() async {
    try {
      final store = PracticeStore(await openPracticeDb());
      if (!mounted) {
        await store.close();
        return;
      }
      setState(() => _store = store);
    } catch (_) {
      // no history this session; the scale screen still grades
    }
  }

  @override
  void dispose() {
    _store?.close();
    super.dispose();
  }

  /// The scale data and the grading thresholds ship with the app (ADR 0011, ADR 0012); the defaults stand if the config cannot be read.
  Future<void> _loadScaleAssets() async {
    final lib = ScaleLibrary.fromJsonString(await rootBundle.loadString('assets/scales/beginner.json'));
    var cfg = const GradingConfig();
    try {
      cfg = GradingConfig.fromJsonString(await rootBundle.loadString('assets/config/grading.json'));
    } on Exception {
      // keep the defaults (the same values)
    }
    var coaching = const CoachingConfig();
    try {
      coaching = CoachingConfig.fromJsonString(await rootBundle.loadString('assets/config/coaching.json'));
    } on Exception {
      // keep the defaults (the same values, ADR 0016)
    }
    if (!mounted) return;
    setState(() {
      _library = lib;
      _grading = cfg;
      _coaching = coaching;
    });
  }

  EngineFactory get _engineFactory => (p) => FfiEngine(_bindings, Pointer<intono_engine>.fromAddress(p));

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: _heatmap
            ? HeatmapScreen(
                load: () async {
                  final store = _store;
                  if (store == null) throw StateError('the practice history is not open');
                  return heatmapOf(await store.gradedNotesSince(DateTime.now().toUtc().subtract(const Duration(days: 30))));
                },
                config: _grading,
                onClose: () => setState(() => _heatmap = false),
              )
            : _settings
            ? SettingsScreen(
                onClearHistory: () async {
                  final store = _store;
                  if (store == null) throw StateError('the practice history is not open');
                  await store.clearHistory();
                },
                onClose: () => setState(() => _settings = false),
              )
            : _scales && _library != null
            ? ScaleScreen(
                audio: _audio,
                engineFactory: _engineFactory,
                library: _library!,
                config: _grading,
                onClose: () => setState(() => _scales = false),
                coach: (r) async {
                  final store = _store;
                  final history = store == null
                      ? [for (final n in storedNotesOf(r)) ('this run', n)]
                      : await store.gradedNotesSince(DateTime.now().toUtc().subtract(const Duration(days: 30)));
                  return coachingTips(history: history, run: r, library: _library!, grading: _grading, config: _coaching);
                },
                onRunFinished: (r, started, ended) async {
                  final store = _store;
                  if (store == null) throw StateError('the practice history is not open');
                  await store.saveRun(r, startedAt: started, endedAt: ended);
                },
              )
            : _bench
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
                onOpenScales: _library == null ? null : () => setState(() => _scales = true),
                onOpenSettings: () => setState(() => _settings = true),
                onOpenHeatmap: () => setState(() => _heatmap = true),
              ),
      );
}
