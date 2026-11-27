import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'audio_control.dart';
import 'bench_runner.dart';
import 'debug_screen.dart' show Disposable, EngineFactory;
import 'engine_api.dart';
import 'frame_poller.dart';
import 'ui_button.dart';

/// Bench mode (ADR 0009 decision 5): fixed scenarios, a text report, timings only, never audio.
///
/// Run: worst hop on a generated signal in the product build and in the guard-off comparison build, then [captureSeconds] of real
/// capture for the latency, xrun, gap and slow-hop facts of the live stream.
///
/// Soak (ADR 0008 W3/W4 and the polling power cost): [soakDuration] of real capture with the worker latency probe armed and the queue
/// sampled once a second, while the UI polls the engine at vsync as the meter does. The inline baseline runs the same without the worker
/// thread; the battery difference between the two runs is the cost of the worker's 2 ms poll. The screen stays on during a soak.
class BenchScreen extends StatefulWidget {
  const BenchScreen({
    super.key,
    required this.audio,
    required this.runner,
    required this.onClose,
    this.engineFactory,
    this.runs = 10,
    this.captureSeconds = 10,
    this.soakDuration = const Duration(minutes: 30),
  });

  final AudioControl audio;
  final BenchRunner runner;
  final VoidCallback onClose;

  /// Wraps the engine pointer for frame polling during a soak. Null: the soak runs without UI polling.
  final EngineFactory? engineFactory;
  final int runs;
  final int captureSeconds;
  final Duration soakDuration;

  @override
  State<BenchScreen> createState() => _BenchScreenState();
}

class _BenchScreenState extends State<BenchScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _running = false;
  bool _soaking = false;
  String _report = '';
  String _soakStatus = '';
  Timer? _soakEnd;
  Timer? _soakRefresh;
  PollingController? _poll;
  EngineApi? _engine;

  int get _soakMinutes => (widget.soakDuration.inSeconds / 60).ceil();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _soakEnd?.cancel();
    _soakRefresh?.cancel();
    _stopPolling();
    if (_soaking) widget.audio.stop();
    super.dispose();
  }

  /// Capture never continues in the background: a soak that loses the foreground ends there, with what it measured.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_soaking && (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached)) {
      _finishSoak(note: 'the app left the foreground');
    }
  }

  Future<void> _run() async {
    if (_running || _soaking) return;
    setState(() {
      _running = true;
      _report = '';
    });
    final b = StringBuffer('Intono bench\n');
    final product = await widget.runner.run(BenchLibrary.product, widget.runs);
    b.writeln(product ?? 'product build: bench not available');
    final noGuard = await widget.runner.run(BenchLibrary.noGuard, widget.runs);
    b.writeln(noGuard ?? 'comparison build (guard OFF): not in this APK');
    if (await widget.audio.start()) {
      await Future<void>.delayed(Duration(seconds: widget.captureSeconds));
      b.writeln('capture ${widget.captureSeconds} s:');
      b.writeln(await widget.audio.info());
      await widget.audio.stop();
    } else {
      b.writeln('capture: could not start: ${await widget.audio.lastError()}');
    }
    if (!mounted) return;
    setState(() {
      _running = false;
      _report = b.toString().trimRight();
    });
  }

  Future<void> _startSoak({required bool inlineEngine}) async {
    if (_running || _soaking) return;
    setState(() {
      _running = true;
      _report = '';
      _soakStatus = 'starting';
    });
    final ok = await widget.audio.startSoak(minutes: _soakMinutes, inlineEngine: inlineEngine);
    if (!mounted) return;
    if (!ok) {
      final err = await widget.audio.lastError();
      if (!mounted) return;
      setState(() {
        _running = false;
        _soakStatus = '';
        _report = 'soak: could not start: ${err.isEmpty ? 'unknown error' : err}';
      });
      return;
    }
    final factory = widget.engineFactory;
    if (factory != null) {
      final pointer = await widget.audio.enginePointer();
      if (!mounted) return;
      if (pointer != 0) {
        _engine = factory(pointer);
        _poll = PollingController(vsync: this, engine: _engine!)..start();
      }
    }
    setState(() {
      _running = false;
      _soaking = true;
    });
    _soakEnd = Timer(widget.soakDuration, _finishSoak);
    _soakRefresh = Timer.periodic(const Duration(seconds: 5), (_) async {
      final s = await widget.audio.soakStatus();
      if (mounted && _soaking) setState(() => _soakStatus = s);
    });
  }

  void _stopPolling() {
    _poll?.dispose();
    _poll = null;
    final e = _engine;
    if (e is Disposable) (e as Disposable).dispose();
    _engine = null;
  }

  Future<void> _finishSoak({String? note}) async {
    if (!_soaking) return;
    _soaking = false;
    _soakEnd?.cancel();
    _soakRefresh?.cancel();
    _stopPolling(); // polling first: after finishSoak the engine pointer is dead
    final report = await widget.audio.finishSoak();
    if (!mounted) return;
    setState(() {
      _soakStatus = '';
      _report = ['Intono soak', if (note != null) 'ended because $note', report.trimRight()].join('\n');
    });
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFF101418),
        child: SafeArea(
          child: DefaultTextStyle(
            style: const TextStyle(color: Color(0xFFE8ECEF), fontSize: 14, decoration: TextDecoration.none),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppButton(label: 'Back', onTap: _soaking ? () {} : widget.onClose),
                  const SizedBox(height: 12),
                  AppButton(label: _running && !_soaking ? 'Running...' : 'Run', onTap: _run),
                  const SizedBox(height: 12),
                  if (!_soaking) ...[
                    AppButton(label: 'Soak $_soakMinutes min (worker)', onTap: () => _startSoak(inlineEngine: false)),
                    const SizedBox(height: 12),
                    AppButton(label: 'Soak $_soakMinutes min (inline baseline)', onTap: () => _startSoak(inlineEngine: true)),
                  ] else ...[
                    AppButton(label: 'Stop soak', onTap: () => _finishSoak(note: 'Stop soak was pressed')),
                    const SizedBox(height: 8),
                    Text('soak running: $_soakStatus'),
                  ],
                  const SizedBox(height: 12),
                  if (_report.isNotEmpty) AppButton(label: 'Copy', onTap: () => Clipboard.setData(ClipboardData(text: _report))),
                  const SizedBox(height: 12),
                  if (_report.isNotEmpty) Text(_report, key: const Key('bench-report')),
                ],
              ),
            ),
          ),
        ),
      );
}
