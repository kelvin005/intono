import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../audio_control.dart';
import '../debug_screen.dart' show Disposable, EngineFactory;
import '../engine_api.dart';
import '../frame_poller.dart';
import '../meter_state.dart' show noteName;
import '../speech.dart';
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
/// results: the score with the 🟢/🟡/🔴 counts and every note coloured, with "Play again". The microphone feeds the engine only during a
/// run; in review the session stays open for replay (ADR 0013): tap a note, or "Play the run".
class ScaleScreen extends StatefulWidget {
  const ScaleScreen({
    super.key,
    required this.audio,
    required this.engineFactory,
    required this.library,
    required this.config,
    required this.onClose,
    this.onRunFinished,
    this.coach,
    this.speech,
    this.speakSummary,
  });

  final AudioControl audio;
  final EngineFactory engineFactory;
  final ScaleLibrary library;
  final GradingConfig config;
  final VoidCallback onClose;

  /// A finished run (the last note played, Stop, or the app leaving the foreground), for the practice history (ADR 0015). Called once
  /// per run; the store skips a run with no played note. Null: nothing is stored.
  final Future<void> Function(ScaleResult result, DateTime startedAt, DateTime endedAt)? onRunFinished;

  /// The coaching tips for a finished run (ADR 0016), asked for after [onRunFinished] completes so the history includes the run.
  final Future<List<String>> Function(ScaleResult result)? coach;

  /// The spoken summary (ADR 0017): spoken after the run, once capture has ended (the microphone is off), if [speakSummary] says so.
  final SpeechControl? speech;
  final Future<bool> Function()? speakSummary;

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
  List<String> _tips = const [];
  bool _speaking = false;
  bool _starting = false;
  DateTime _runStarted = DateTime.now();
  DateTime _runEnded = DateTime.now();
  bool _savePrompt = false; // a bad run (most notes missed or wrong): ask before it enters the history
  bool _declined = false;
  ScaleSuggestion? _suggestion; // the run fits another octave or scale much better: "Switch?"
  bool _shifted = false; // the results are regraded at another octave: display only, never stored
  // Replay (ADR 0013): armed with each run; during review the session stays open (input paused) for playback.
  bool _replayArmed = false;
  bool _reviewOpen = false;   // the audio session is still open for the review
  bool _playing = false;
  Timer? _playPoll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSpeech();
    _playPoll?.cancel();
    _playPoll = null;
    if (_reviewOpen) {
      // the screen closes during review: release (zero) the ring, then close the session (ADR 0013)
      _reviewOpen = false;
      _replayArmed = false;
      widget.audio.replayRelease().then((_) => widget.audio.stop());
    } else {
      _stopCapture();
    }
    super.dispose();
  }

  /// Capture never continues in the background: a run that loses the foreground ends there and shows what was graded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused && state != AppLifecycleState.hidden) return;
    _stopSpeech();
    if (_phase == _Phase.run) _finish(keepReplay: false); // ADR 0013: nothing is kept when the app leaves the foreground
    if (_reviewOpen) _endReview();
  }

  Future<void> _start(ScaleDef s) async {
    if (_starting) return;
    _starting = true;
    setState(() => _error = '');
    if (_reviewOpen) await _endReview(); // a new run releases the old one first (ADR 0013)
    if (!mounted) return;
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
    _replayArmed = await widget.audio.replayArm(); // the last 60 s of the run, in RAM only (ADR 0013)
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
      _tips = const [];
      _savePrompt = false;
      _declined = false;
      _suggestion = null;
      _shifted = false;
      _runStarted = DateTime.now();
      _phase = _Phase.run;
    });
  }

  /// Ends grading. With [keepReplay] and an armed ring the session stays open for the review (input paused); otherwise the ring is
  /// released and capture closes.
  void _stopCapture({bool keepReplay = false}) {
    _poll?.dispose();
    _poll = null;
    final e = _engine;
    e?.setExpected(const []); // free mode again before the engine is released
    if (e is Disposable) (e as Disposable).dispose();
    _engine = null;
    if (keepReplay && _replayArmed) {
      widget.audio.replayFreeze();
      _reviewOpen = true;
    } else {
      if (_replayArmed) widget.audio.replayRelease();
      _replayArmed = false;
      widget.audio.stop();
    }
  }

  /// Ends the review: stops playback, releases (zeroes) the ring, then closes the session.
  Future<void> _endReview() async {
    _stopSpeech();
    if (!_reviewOpen) return;
    _reviewOpen = false;
    _replayArmed = false;
    _playPoll?.cancel();
    _playPoll = null;
    _playing = false;
    await widget.audio.replayRelease();
    await widget.audio.stop();
    if (mounted) setState(() {});
  }

  Future<void> _play(double from, double to) async {
    if (!_reviewOpen) return;
    _stopSpeech(); // the summary and the replay would talk over each other
    final ok = await widget.audio.replayPlay(from, to);
    if (!mounted || !ok) return;
    setState(() => _playing = true);
    _playPoll?.cancel();
    _playPoll = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      final still = await widget.audio.replayPlaying();
      if (!mounted || still) return;
      _playPoll?.cancel();
      _playPoll = null;
      setState(() => _playing = false);
    });
  }

  Future<void> _stopPlayback() async {
    _playPoll?.cancel();
    _playPoll = null;
    await widget.audio.replayStop();
    if (mounted) setState(() => _playing = false);
  }

  void _finish({bool keepReplay = true}) {
    if (_phase != _Phase.run) return;
    final result = _run!.result();
    _stopCapture(keepReplay: keepReplay && !result.notHeard); // nothing heard: nothing to replay
    final ended = DateTime.now();
    final suggestion = result.notHeard ? null : _run!.suggestion(widget.library);
    setState(() {
      _result = result;
      _runEnded = ended;
      _suggestion = suggestion;
      _shifted = false;
      _savePrompt = result.badRun || suggestion != null;
      _declined = false;
      _phase = _Phase.results;
    });
    // "I didn't hear you play": no grade, no save, no tips, no heatmap. A bad run, or one that fits another octave or scale much better,
    // waits for the player's answer ("Switch?", "Save this run?").
    if (!result.notHeard && !result.badRun && suggestion == null) _save(result, _runStarted, ended);
  }

  /// Regrades the same notes against the suggested octave or scale. A scale is a real run of that scale (saved if it is good); an
  /// octave is shown only: the string and finger data would be wrong for the notes played, so it never reaches the history.
  void _switchTo(ScaleSuggestion s) {
    final run = _run;
    if (run == null || _phase != _Phase.results) return;
    final r = run.regrade(s.scale);
    final shifted = s.kind == SuggestionKind.octave;
    setState(() {
      _result = r;
      _suggestion = null;
      _shifted = shifted;
      _savePrompt = !shifted && r.badRun;
      _declined = false;
      _tips = const [];
    });
    if (!shifted && !r.notHeard && !r.badRun) _save(r, _runStarted, _runEnded);
  }

  void _answerSave(bool yes) {
    final r = _result;
    if (r == null || !_savePrompt) return;
    setState(() {
      _savePrompt = false;
      _declined = !yes;
    });
    if (yes) _save(r, _runStarted, _runEnded);
  }

  Future<void> _save(ScaleResult r, DateTime started, DateTime ended) async {
    final save = widget.onRunFinished;
    if (save != null) {
      try {
        await save(r, started, ended);
      } catch (_) {
        if (mounted) setState(() => _saveError = 'This run could not be saved to your history.');
      }
    }
    final coach = widget.coach;
    var tips = const <String>[];
    if (coach != null) {
      try {
        tips = await coach(r);
        if (mounted && identical(_result, r)) setState(() => _tips = tips);
      } catch (_) {
        // no tips this time; the results stand on their own
      }
    }
    await _speak(r, tips);
  }

  /// ADR 0017: only on the results, after _stopCapture (capture frozen or closed: the microphone is off), never during a run.
  Future<void> _speak(ScaleResult r, List<String> tips) async {
    final speech = widget.speech;
    final ask = widget.speakSummary;
    if (speech == null || ask == null || _phase != _Phase.results || !identical(_result, r)) return;
    bool yes;
    try {
      yes = await ask();
    } catch (_) {
      yes = false;
    }
    if (!yes || !mounted || _phase != _Phase.results || !identical(_result, r)) return;
    _speaking = true;
    await speech.speak(spokenSummary(r, tips));
  }

  void _stopSpeech() {
    if (!_speaking) return;
    _speaking = false;
    widget.speech?.stop();
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
              Text('${run.result().notes.where((g) => g.heard != null).length} of ${_scale!.notes.length} notes'),
              const Spacer(),
              AppButton(label: 'Stop', onTap: _finish),
            ],
          ),
        ),
      ),
    );
  }

  void _playRun(ScaleResult r) {
    final played = [for (final g in r.notes) if (g.heard != null) g.heard!];
    if (played.isEmpty) return;
    final from = played.map((p) => p.tStart).reduce((a, b) => a < b ? a : b);
    final to = played.map((p) => p.tEnd).reduce((a, b) => a > b ? a : b);
    _play(from - 0.2, to + 0.3);
  }

  static String _playedName(Note n) => noteName((n.midiNote + n.meanCents / 100).round());

  /// Nothing (or almost nothing) was heard: no grade, no save, no tips (GradingConfig.minHeardFraction).
  Widget _notHeard(ScaleResult r) => ColoredBox(
        color: ScaleColors.neutral,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.scale.title, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 16),
              const Text("I didn't hear you play. Check the microphone, come closer, or play louder.", style: TextStyle(fontSize: 20)),
              const SizedBox(height: 24),
              AppButton(label: 'Play again', onTap: () => _start(r.scale)),
              const SizedBox(height: 12),
              AppButton(label: 'Scales', onTap: () => setState(() => _phase = _Phase.pick)),
            ]),
          ),
        ),
      );

  Widget _results() {
    final r = _result!;
    if (r.notHeard) return _notHeard(r);
    String cents(double? c) => c == null ? 'missed' : '${c >= 0 ? '+' : ''}${c.toStringAsFixed(0)}¢';
    String where(ScaleNote n) => _shifted
        ? '' // the string and finger of the chosen octave mean nothing at the octave that was played
        : '${n.string} ${n.finger == 0 ? 'open' : '${n.finger}${n.placement == null ? '' : ' ${n.placement}'}'}';
    // ADR 0018 note: a note far from the expected one also names the nearest semitone
    String hint(GradedNote g) {
      final h = neighbourHint(g, widget.config);
      return h == null ? '' : '${h.closer ? 'sounds closer to' : 'almost'} ${h.name}';
    }
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
            if (_shifted)
              const Padding(padding: EdgeInsets.only(top: 8), child: Text('Graded at the octave you played. Not added to your progress.')),
            if (_suggestion != null) ...[
              const SizedBox(height: 12),
              Text(_suggestion!.message),
              const SizedBox(height: 8),
              AppButton(label: 'Switch', onTap: () => _switchTo(_suggestion!)),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in r.notes)
                  GestureDetector(
                    key: ValueKey('result-note:${g.index}'),
                    // ADR 0013: a played note replays its own slice, 50 ms either side
                    onTap: g.heard == null || !_reviewOpen ? null : () => _play(g.heard!.tStart - 0.05, g.heard!.tEnd + 0.05),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      color: ScaleColors.of(g.isWrong ? Grade.red : g.grade),
                      // a wrong note is named, never given cents; its expected note counts as missed
                      child: Text(
                          g.isWrong
                              ? ['played ${g.wrongName}, expected ${g.expected.name}', where(g.expected)].where((l) => l.isNotEmpty).join('\n')
                              : [g.expected.name, cents(g.cents), where(g.expected), hint(g)].where((l) => l.isNotEmpty).join('\n'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
            if (r.extras.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('${r.extras.length} extra notes: ${r.extras.take(8).map(_playedName).join(', ')}${r.extras.length > 8 ? ', ...' : ''}')),
            if (_savePrompt) ...[
              const SizedBox(height: 16),
              Text(r.badRun ? 'Most notes were missed or wrong. Save this run?' : 'Save this run?'),
              const SizedBox(height: 8),
              // the default is No: it comes first and a run left unanswered is not saved
              AppButton(label: "Don't save", onTap: () => _answerSave(false)),
              const SizedBox(height: 8),
              AppButton(label: 'Save', onTap: () => _answerSave(true)),
            ],
            if (_declined) const Padding(padding: EdgeInsets.only(top: 12), child: Text('Not saved to your progress.')),
            if (_saveError.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_saveError)),
            for (final tip in _tips) Padding(padding: const EdgeInsets.only(top: 12), child: Text(tip)),
            if (_reviewOpen && r.notes.any((g) => g.heard != null)) ...[
              const SizedBox(height: 20),
              const Text('Tap a note to hear it.', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              _playing
                  ? AppButton(label: 'Stop playback', onTap: _stopPlayback)
                  : AppButton(label: 'Play the run', onTap: () => _playRun(r)),
            ],
            const SizedBox(height: 20),
            AppButton(label: 'Play again', onTap: () => _start(r.scale.octaveShift != 0 ? _scale! : r.scale)),
            const SizedBox(height: 12),
            AppButton(
                label: 'Scales',
                onTap: () async {
                  await _endReview();
                  if (mounted) setState(() => _phase = _Phase.pick);
                }),
          ]),
        ),
      ),
    );
  }
}
