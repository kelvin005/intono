/// One analysis frame (the Dart view of intono_frame).
class Frame {
  const Frame({
    required this.tSec,
    required this.hz,
    required this.confidence,
    required this.midiNote,
    required this.cents,
    required this.vibratoRateHz,
    required this.vibratoWidthCents,
    required this.isVoiced,
    required this.isOnset,
  });

  final double tSec;
  final double hz;
  final double confidence;
  final int midiNote;
  final double cents;
  final double vibratoRateHz;
  final double vibratoWidthCents;
  final bool isVoiced;
  final bool isOnset;
}

/// One played-note summary (the Dart view of intono_note).
class Note {
  const Note({
    required this.tStart,
    required this.tEnd,
    required this.midiNote,
    required this.meanCents,
    required this.stdCents,
    required this.vibratoRateHz,
    required this.vibratoWidthCents,
    required this.meanConfidence,
    required this.frameCount,
  });

  final double tStart;
  final double tEnd;
  final int midiNote;
  final double meanCents;
  final double stdCents;
  final double vibratoRateHz;
  final double vibratoWidthCents;
  final double meanConfidence;
  final int frameCount;
}

/// The engine as the UI sees it. Every call is UI-thread only (the C API's rule for the read functions). The real implementation is
/// FfiEngine; tests use a scripted fake.
abstract class EngineApi {
  /// Frames one [readFrames] call can return at most.
  int get frameCapacity;

  /// Reads the queued frames, oldest first, into a buffer that is reused by the next call. Returns how many.
  int readFrames();

  /// Frame [i] of the last [readFrames] batch.
  Frame frameAt(int i);

  /// Reads the queued note summaries, oldest first. Returns how many.
  int readNotes();

  /// Note [i] of the last [readNotes] batch.
  Note noteAt(int i);

  /// Scale mode (ADR 0014): the MIDI notes the player should play, in order (at most 128 are used). Empty: free mode.
  void setExpected(List<int> midiNotes);
}
