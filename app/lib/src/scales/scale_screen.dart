import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../audio_control.dart';
import '../debug_screen.dart' show Disposable, EngineFactory;
import '../engine_api.dart';
import '../frame_poller.dart';
import '../ui_button.dart';
import 'grader.dart';
import 'grading_config.dart';
import 'scale.dart';
import 'scale_run.dart';

/// The glance colours (architecture doc, "Practising without staring"): readable in peripheral vision from the music stand.
class ScaleColors {
  static const neutral = Color(0xFF101418);
  static const green = Color(0xFF1E8E3E);
  static const yellow = Color(0xFFE3B505);
  static const red = Color(0xFFC62828);
  static const missed = Color(0xFF3A4048);

  static Color of(Grade? g) => switch (g) {
        null => neutral,
        Grade.green => green,
        Grade.yellow => yellow,
        Grade.red => red,
        Grade.missed => missed,
      };
}

enum _Phase { pick, run, results }

/// Scale mode (ADR 0011 item 4): choose a scale, play it with the glance view (the whole screen the colour of the last note), then the
/// results: the score with the 🟢/🟡/🔴 counts and every note coloured, with "Play again". Capture runs only during a run.
class ScaleScreen extends StatefulWidget {
  const ScaleScreen({
    super.key,
    required this.audio,
    required this.engineFactory,
    required this.library,
    required this.config,
    required this.onClose,
    this.onRunFinished,
  });

  final AudioControl audio;
  final EngineFactory engineFactory;
  final ScaleLibrary library;
  final GradingConfig config;
  final VoidCallback onClose;

  /// A finished run (the last note played, Stop, or the app leaving the foreground), for the practice history (ADR 0015). Called once
  /// per run; the store skips a run with no played note. Null: nothing is stored.
  final Future<void> Function(ScaleResult result, DateTime startedAt, DateTime endedAt)? onRunFinished;

  @override
  State<ScaleScreen> createState() => _ScaleScreenState();
}

class _ScaleScreenState extends State<ScaleScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  _Phase _phase = _Phase.pick;
  ScaleDef? _scale;
  ScaleRun? _run;
  ScaleResult? _result;
  PollingController? _poll;
  EngineApi? _engine;
  String _error = '';
  String _saveError = '';
  bool _starting = false;
  DateTime _runStarted = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCapture();
    super.dispose();
  }

  /// Capture never continues in the background: a run that loses the foreground ends there and shows what was graded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_phase == _Phase.run && (state == AppLifecycleState.paused || state == AppLifecycleState.hidden)) _finish();
  }

  Future<void> _start(ScaleDef s) async {
    if (_starting) return;
    _starting = true;
    setState(() => _error = '');
    final ok = await widget.audio.start();
    if (!mounted) return;
    if (!ok) {
      final err = await widget.audio.lastError();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _phase = _Phase.pick;
        _error = 'Cannot start: ${err.isEmpty ? 'unknown error' : err}';
      });
      return;
    }
    final pointer = await widget.audio.enginePointer();
    if (!mounted) return;
    final run = ScaleRun(s, widget.config);
    _engine = widget.engineFactory(pointer);
    _engine!.setExpected([for (final n in s.notes) n.midi]); // score-informed segmentation (ADR 0014)
    _poll = PollingController(vsync: this, engine: _engine!, onNotes: (notes) {
      run.addNotes(notes);
      if (run.complete) {
        SchedulerBinding.instance.addPostFrameCallback((_) => _finish());
      }
      if (mounted) setState(() {});
    })
      ..start();
    setState(() {
      _starting = false;
      _scale = s;
      _run = run;
      _result = null;
      _saveError = '';
      _runStarted = DateTime.now();
      _phase = _Phase.run;
    });
  }

  void _stopCapture() {
    _poll?.dispose();
    _poll = null;
    final e = _engine;
    e?.setExpected(const []); // free mode again before the engine is released
    if (e is Disposable) (e as Disposable).dispose();
    _engine = null;
    widget.audio.stop();
  }

  void _finish() {
    if (_phase != _Phase.run) return;
    _stopCapture();
    final result = _run!.result();
    setState(() {
      _result = result;
      _phase = _Phase.results;
    });
    _save(result, _runStarted, DateTime.now());
  }

  Future<void> _save(ScaleResult r, DateTime started, DateTime ended) async {
    final save = widget.onRunFinished;
    if (save == null) return;
    try {
      await save(r, started, ended);
    } catch (_) {
      if (mounted) setState(() => _saveError = 'This run could not be saved to your history.');
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFE8ECEF), fontSize: 16, decoration: TextDecoration.none),
        child: switch (_phase) {
          _Phase.pick => _picker(),
          _Phase.run => _glance(),
          _Phase.results => _results(),
        },
      );

  Widget _picker() => ColoredBox(
        color: ScaleColors.neutral,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppButton(label: 'Back', onTap: widget.onClose),
              const SizedBox(height: 12),
              const Text('Choose a scale', style: TextStyle(fontSize: 22)),
              if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error)),
              const SizedBox(height: 12),
              for (final s in widget.library.scales)
                GestureDetector(
                  key: ValueKey('scale-tile:${s.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _start(s),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(s.title)),
                ),
            ]),
          ),
        ),
      );

  /// The glance view: the whole screen is the colour of the last graded note; a small label says which scale and how far.
  Widget _glance() {
    final run = _run!;
    return ColoredBox(
      key: const Key('glance'),
      color: ScaleColors.of(run.latestGrade),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_scale!.title, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 6),
              Text('${run.result().notes.where((g) => g.played != null).length} of ${_scale!.notes.length} notes'),
              const Spacer(),
              AppButton(label: 'Stop', onTap: _finish),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results() {
    final r = _result!;
    String cents(double? c) => c == null ? 'missed' : '${c >= 0 ? '+' : ''}${c.toStringAsFixed(0)}¢';
    String where(ScaleNote n) =>
        '${n.string} ${n.finger == 0 ? 'open' : '${n.finger}${n.placement == null ? '' : ' ${n.placement}'}'}';
    return ColoredBox(
      color: ScaleColors.neutral,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.scale.title, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            Text('${r.scorePercent.round()} %', style: const TextStyle(fontSize: 48)),
            Text('🟢 ${r.green}   🟡 ${r.yellow}   🔴 ${r.red + r.missed}'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in r.notes)
                  Container(
                    key: ValueKey('result-note:${g.index}'),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    color: ScaleColors.of(g.grade),
                    child: Text('${g.expected.name}\n${cents(g.cents)}\n${where(g.expected)}',
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            if (r.extras.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text('${r.extras.length} extra notes')),
            if (_saveError.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_saveError)),
            const SizedBox(height: 20),
            AppButton(label: 'Play again', onTap: () => _start(r.scale)),
            const SizedBox(height: 12),
            AppButton(label: 'Scales', onTap: () => setState(() => _phase = _Phase.pick)),
          ]),
        ),
      ),
    );
  }
}
