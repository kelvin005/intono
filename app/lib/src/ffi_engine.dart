import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'debug_screen.dart' show Disposable;
import 'engine_api.dart';
import 'ffi/intono_bindings.dart';

/// The engine over dart:ffi. The buffers are allocated once and reused by every read, so polling allocates nothing but the Frame
/// object of the newest frame. Does not own the engine: the platform side creates and destroys it, so [dispose] only frees the buffers
/// and must run before the platform stops the engine.
class FfiEngine implements EngineApi, Disposable {
  FfiEngine(this._lib, this._engine, {int capacity = 64, int noteCapacity = 64})
      : _capacity = capacity,
        _noteCapacity = noteCapacity,
        _frames = calloc<intono_frame>(capacity),
        _notes = calloc<intono_note>(noteCapacity);

  final IntonoBindings _lib;
  final Pointer<intono_engine> _engine;
  final int _capacity;
  final int _noteCapacity;
  final Pointer<intono_frame> _frames;
  final Pointer<intono_note> _notes;
  bool _disposed = false;

  @override
  int get frameCapacity => _capacity;

  @override
  int readFrames() => _disposed ? 0 : _lib.intono_read_frames(_engine, _frames, _capacity);

  @override
  Frame frameAt(int i) {
    final f = (_frames + i).ref;
    return Frame(
      tSec: f.t_sec,
      hz: f.hz,
      confidence: f.confidence,
      midiNote: f.midi_note,
      cents: f.cents,
      vibratoRateHz: f.vibrato_rate_hz,
      vibratoWidthCents: f.vibrato_width_cents,
      isVoiced: f.is_voiced != 0,
      isOnset: f.is_onset != 0,
    );
  }

  @override
  int readNotes() => _disposed ? 0 : _lib.intono_read_notes(_engine, _notes, _noteCapacity);

  @override
  Note noteAt(int i) {
    final n = (_notes + i).ref;
    return Note(
      tStart: n.t_start,
      tEnd: n.t_end,
      midiNote: n.midi_note,
      meanCents: n.mean_cents,
      stdCents: n.std_cents,
      vibratoRateHz: n.vibrato_rate_hz,
      vibratoWidthCents: n.vibrato_width_cents,
      meanConfidence: n.mean_confidence,
      frameCount: n.frame_count,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    calloc.free(_frames);
    calloc.free(_notes);
  }
}
