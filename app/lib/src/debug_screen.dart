import 'dart:async';
import 'dart:ui' show FrameTiming, FramePhase;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'audio_control.dart';
import 'drone_policy.dart';
import 'engine_api.dart';
import 'frame_poller.dart';
import 'jank_log.dart';
import 'meter_state.dart';
import 'meter_view.dart';
import 'ui_button.dart';

typedef EngineFactory = EngineApi Function(int enginePointer);

/// The Phase 2 screen: live meter (note, cents, needle) over the Start/Stop and drone controls and the stream facts. It also carries what
/// the Android harness shows, so the harness can be retired (ADR 0009 Note 1).
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key, required this.audio, required this.engineFactory, this.onOpenBench, this.onOpenScales});

  final AudioControl audio;
  final EngineFactory engineFactory;

  /// Called after a long press on the version label (capture is stopped first). Null: no bench in this build.
  final VoidCallback? onOpenBench;

  /// Opens scale mode (ADR 0011); capture is stopped first, the scale screen starts its own.
  final VoidCallback? onOpenScales;

  @override
  State<DebugScreen> createState() => _DebugScreenState();
}

class _DebugScreenState extends State<DebugScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  PollingController? _controller;
  EngineApi? _engine;
  bool _running = false;
  bool _busy = false;
  bool? _userDrone;
  bool _headphones = false;
  String _info = 'stopped';
  final ValueNotifier<MeterState> _meter = ValueNotifier<MeterState>(MeterState.silent);
  final JankLog _jank = JankLog();
  Timer? _refresh;
  bool _timingsAttached = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _teardownPolling();
    _meter.dispose();
    super.dispose();
  }

  /// Capture never continues in the background: stop before the app is hidden (the platform side does not stop it on its own, so the
  /// engine cannot vanish under a polling Ticker).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_running && (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached)) {
      _stop();
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _jank.add(t.timestampInMicroseconds(FramePhase.vsyncStart), t.totalSpan.inMicroseconds);
    }
  }

  /// The stream facts are live while running: twice a second (the first reading after Start has no hops yet).
  void _startRefresh() {
    _refresh?.cancel();
    _refresh = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      final info = await widget.audio.info();
      if (!mounted || !_running) return;
      setState(() => _info = info);
    });
  }

  void _stopRefresh() {
    _refresh?.cancel();
    _refresh = null;
    if (_timingsAttached) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _timingsAttached = false;
    }
  }

  void _teardownPolling() {
    _stopRefresh();
    _controller?.meter.removeListener(_forward);
    _controller?.dispose();
    _controller = null;
    final e = _engine;
    if (e is Disposable) (e as Disposable).dispose();
    _engine = null;
  }

  void _forward() => _meter.value = _controller!.meter.value;

  Future<void> _start() async {
    if (_busy || _running) return;
    setState(() => _busy = true);
    final ok = await widget.audio.start();
    if (!mounted) return;
    if (!ok) {
      final err = await widget.audio.lastError();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _info = err.isEmpty ? 'could not start' : err;
      });
      return;
    }
    final pointer = await widget.audio.enginePointer();
    final headphones = await widget.audio.headphonesConnected();
    if (!mounted) return;
    _engine = widget.engineFactory(pointer);
    _controller = PollingController(vsync: this, engine: _engine!)..meter.addListener(_forward);
    _controller!.start();
    _jank.clear();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _timingsAttached = true;
    _headphones = headphones;
    final drone = DronePolicy.decide(_userDrone, _headphones);
    if (drone.play) await widget.audio.setDrone(true);
    final info = await widget.audio.info();
    if (!mounted) return;
    setState(() {
      _running = true;
      _busy = false;
      _info = info;
    });
    _startRefresh();
  }

  Future<void> _stop() async {
    if (_busy || !_running) return;
    setState(() => _busy = true);
    _teardownPolling(); // polling and buffers first: after audio.stop() the engine pointer is dead
    _meter.value = MeterState.silent;
    await widget.audio.stop();
    if (!mounted) return;
    setState(() {
      _running = false;
      _busy = false;
      _info = 'stopped';
    });
  }

  Future<void> _openBench() async {
    final open = widget.onOpenBench;
    if (open == null) return;
    await _stop();   // the bench needs the device quiet, and the engine must not outlive its stream
    if (mounted) open();
  }

  Future<void> _openScales() async {
    final open = widget.onOpenScales;
    if (open == null) return;
    await _stop();
    if (mounted) open();
  }

  Future<void> _toggleDrone() async {
    final now = DronePolicy.decide(_userDrone, _headphones).play;
    _userDrone = !now;
    if (_running) await widget.audio.setDrone(!now);
    final info = _running ? await widget.audio.info() : _info;
    if (!mounted) return;
    setState(() => _info = info);
  }

  Future<void> _refreshInfo() async {
    final info = await widget.audio.info();
    if (!mounted) return;
    setState(() => _info = info);
  }

  @override
  Widget build(BuildContext context) {
    final drone = DronePolicy.decide(_userDrone, _headphones);
    return ColoredBox(
      color: const Color(0xFF101418),
      child: SafeArea(
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFFE8ECEF), fontSize: 16, decoration: TextDecoration.none),
          child: SingleChildScrollView(
            child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<MeterState>(
                  valueListenable: _meter,
                  builder: (context, s, _) => Center(child: MeterView(state: s)),
                ),
                const SizedBox(height: 16),
                AppButton(label: _running ? 'Stop' : 'Start', onTap: _running ? _stop : _start),
                const SizedBox(height: 12),
                AppButton(label: 'Drone: ${drone.play ? 'on' : 'off'}', onTap: _toggleDrone),
                if (widget.onOpenScales != null) ...[
                  const SizedBox(height: 12),
                  AppButton(label: 'Scales', onTap: _openScales),
                ],
                if (drone.warnSpeaker) const Padding(padding: EdgeInsets.only(top: 8), child: Text(DronePolicy.speakerWarning)),
                const SizedBox(height: 16),
                GestureDetector(onTap: _refreshInfo, child: Text(_jank.text.isEmpty ? _info : '$_info\n${_jank.text}')),
                const SizedBox(height: 24),
                GestureDetector(
                  key: const Key('version-label'),
                  onLongPress: _openBench,
                  child: const Text('Intono 0.1.0 (phase 2)', style: TextStyle(color: Color(0xFF6B7885), fontSize: 12)),
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Implemented by engines that own native buffers.
abstract interface class Disposable {
  void dispose();
}
