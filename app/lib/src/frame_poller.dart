import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'engine_api.dart';
import 'meter_state.dart';

/// Drains the engine's frame ring and note ring; keeps only what the display needs (the newest frame, the note count, the last note).
class FramePoller {
  FramePoller(this._engine);

  final EngineApi _engine;
  MeterState _state = MeterState.silent;
  int noteCount = 0;
  Note? lastNote;

  /// Reads every queued frame (in batches of at most the engine's capacity) and returns the state of the newest one. With no new
  /// frame the previous state object is returned unchanged.
  MeterState pollFrames() {
    Frame? newest;
    int n;
    do {
      n = _engine.readFrames();
      if (n > 0) newest = _engine.frameAt(n - 1);
    } while (n == _engine.frameCapacity);
    if (newest != null) {
      _state = newest.isVoiced
          ? MeterState(voiced: true, midiNote: newest.midiNote, cents: newest.cents, hz: newest.hz, tSec: newest.tSec)
          : MeterState.silent;
    }
    return _state;
  }

  void pollNotes() {
    final n = _engine.readNotes();
    if (n > 0) {
      noteCount += n;
      lastNote = _engine.noteAt(n - 1);
    }
  }
}

/// Polls on the frame clock (vsync): every frame the Ticker fires, frames are drained and the meter is updated once; notes are polled
/// about every [noteInterval]. Nothing is polled while stopped. UI isolate only, so the engine's "UI thread" rule holds.
class PollingController {
  PollingController({
    required TickerProvider vsync,
    required EngineApi engine,
    this.noteInterval = const Duration(milliseconds: 100),
  }) : _poller = FramePoller(engine) {
    _ticker = vsync.createTicker(_onTick);
  }

  final Duration noteInterval;
  final FramePoller _poller;
  late final Ticker _ticker;
  Duration _lastNotePoll = Duration.zero;

  final ValueNotifier<MeterState> meter = ValueNotifier<MeterState>(MeterState.silent);
  final ValueNotifier<int> noteCount = ValueNotifier<int>(0);

  Note? get lastNote => _poller.lastNote;
  bool get isTicking => _ticker.isActive;

  void start() {
    if (_ticker.isActive) return;
    _lastNotePoll = Duration.zero;
    _ticker.start();
  }

  void stop() {
    if (_ticker.isActive) _ticker.stop();
  }

  void dispose() {
    stop();
    _ticker.dispose();
    meter.dispose();
    noteCount.dispose();
  }

  void _onTick(Duration elapsed) {
    final s = _poller.pollFrames();
    if (!identical(s, meter.value)) meter.value = s;
    if (elapsed - _lastNotePoll >= noteInterval) {
      _lastNotePoll = elapsed;
      _poller.pollNotes();
      if (_poller.noteCount != noteCount.value) noteCount.value = _poller.noteCount;
    }
  }
}
