import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'audio_control.dart';
import 'bench_runner.dart';
import 'ui_button.dart';

/// Bench mode (ADR 0009 decision 5): a fixed scenario, a text report, timings only, never audio. Worst hop on a generated signal in the
/// product build and in the guard-off comparison build; then [captureSeconds] of real capture for the latency, xrun, gap and slow-hop
/// facts of the live stream.
class BenchScreen extends StatefulWidget {
  const BenchScreen({
    super.key,
    required this.audio,
    required this.runner,
    required this.onClose,
    this.runs = 10,
    this.captureSeconds = 10,
  });

  final AudioControl audio;
  final BenchRunner runner;
  final VoidCallback onClose;
  final int runs;
  final int captureSeconds;

  @override
  State<BenchScreen> createState() => _BenchScreenState();
}

class _BenchScreenState extends State<BenchScreen> {
  bool _running = false;
  String _report = '';

  Future<void> _run() async {
    if (_running) return;
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
                  AppButton(label: 'Back', onTap: widget.onClose),
                  const SizedBox(height: 12),
                  AppButton(label: _running ? 'Running...' : 'Run', onTap: _run),
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
