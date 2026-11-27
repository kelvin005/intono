import 'package:intono_app/src/engine_api.dart';

/// A scripted engine: frames and notes are queued by the test, and read exactly as the real ring would be (oldest first, in batches).
class FakeEngine implements EngineApi {
  FakeEngine({this.capacity = 64});

  final int capacity;
  final List<Frame> queuedFrames = [];
  final List<Note> queuedNotes = [];
  int readFramesCalls = 0;

  /// Every sequence given to [setExpected], in order (ADR 0014).
  final List<List<int>> expectedCalls = [];
  int readNotesCalls = 0;
  List<Frame> _batch = const [];
  List<Note> _noteBatch = const [];

  @override
  int readFrames() {
    readFramesCalls++;
    final n = queuedFrames.length < capacity ? queuedFrames.length : capacity;
    _batch = queuedFrames.sublist(0, n);
    queuedFrames.removeRange(0, n);
    return n;
  }

  @override
  int get frameCapacity => capacity;

  @override
  Frame frameAt(int i) => _batch[i];

  @override
  int readNotes() {
    readNotesCalls++;
    _noteBatch = List.of(queuedNotes);
    queuedNotes.clear();
    return _noteBatch.length;
  }

  @override
  Note noteAt(int i) => _noteBatch[i];

  @override
  void setExpected(List<int> midiNotes) => expectedCalls.add(List.of(midiNotes));
}

Frame frame({double t = 0, double hz = 440, int midi = 69, double cents = 0, bool voiced = true, bool onset = false}) => Frame(
      tSec: t,
      hz: voiced ? hz : 0,
      confidence: voiced ? 0.95 : 0,
      midiNote: midi,
      cents: cents,
      vibratoRateHz: 0,
      vibratoWidthCents: 0,
      isVoiced: voiced,
      isOnset: onset,
    );

Note note({int midi = 69, double mean = 0}) => Note(
      tStart: 0,
      tEnd: 1,
      midiNote: midi,
      meanCents: mean,
      stdCents: 1,
      vibratoRateHz: 0,
      vibratoWidthCents: 0,
      meanConfidence: 0.9,
      frameCount: 100,
    );
