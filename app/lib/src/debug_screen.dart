import 'package:flutter/widgets.dart';

import 'audio_control.dart';
import 'drone_policy.dart';
import 'engine_api.dart';
import 'frame_poller.dart';
import 'meter_state.dart';
import 'meter_view.dart';

typedef EngineFactory = EngineApi Function(int enginePointer);

/// The Phase 2 screen: live meter (note, cents, needle) over the Start/Stop and drone controls and the stream facts. It also carries what
/// the Android harness shows, so the harness can be retired (ADR 0009 Note 1).
class DebugScreen extends StatefulWidget {
  const DebugScreen({super.key, required this.audio, required this.engineFactory});

  final AudioControl audio;
  final EngineFactory engineFactory;

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

  void _teardownPolling() {
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
                _Button(label: _running ? 'Stop' : 'Start', onTap: _running ? _stop : _start),
                const SizedBox(height: 12),
                _Button(label: 'Drone: ${drone.play ? 'on' : 'off'}', onTap: _toggleDrone),
                if (drone.warnSpeaker) const Padding(padding: EdgeInsets.only(top: 8), child: Text(DronePolicy.speakerWarning)),
                const SizedBox(height: 16),
                GestureDetector(onTap: _refreshInfo, child: Text(_info)),
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

class _Button extends StatelessWidget {
  const _Button({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF6B7885)), borderRadius: BorderRadius.circular(8)),
          child: Text(label),
        ),
      );
}
