// Note segmentation (ADR 0003): turns the per-hop stream into one summary per played note.
//
// A note is the run of voiced frames between two boundaries. The boundaries come from outside (NoteTracker,
// ADR 0004: the note HMM, an RMS onset, or the end of a run). A boundary found late carries a `rewind`: that
// many of the newest frames already belong to the NEW note and are moved across.
//
// Statistics are over the RAW guarded pitch (cents re 440 Hz), not the displayed vibrato centre:
// the whole-note mean of the raw pitch is the figure used for grading (ADR 0001), and over whole
// vibrato cycles it equals the centre. The first kHeadSkip frames of a note and the last kTailSkip
// are left out of the pitch statistics (not out of frame_count / times). Robust mean (ADR 0004): a guard zone of
// kGuardS (30 ms of TIME, not frames: dropouts at a noisy step must not stretch it) next to every boundary or note
// start is excluded (a legato step smears the pitch over ~4 frames), and so is any frame within kNbFrames of a boundary whose displayed vibrato centre is nearer the
// neighbouring note than this note: the neighbour is the previous note's measured mean (for the head of a note) or
// the next note's semitone (for its tail), this note is its own measured mean.
// Allocation-free: fixed arrays, no heap, safe on the audio thread.
#pragma once
#include <algorithm>
#include <cmath>

namespace intono {

struct NoteFrame {
  double t = 0.0;     // window-centre time, seconds
  double c = 0.0;     // raw pitch, cents re 440 Hz
  double conf = 0.0;  // YIN confidence
  double vr = 0.0, vw = 0.0;  // vibrato rate (Hz) / width (cents) reported for this frame, 0 = none
  double ctr = 0.0;   // displayed vibrato centre (ADR 0001), cents re 440 Hz
};

struct NoteSummary {
  double t_start = 0.0, t_end = 0.0;
  double mean_c = 0.0, std_c = 0.0;  // cents re 440 Hz, population std
  double vib_rate = 0.0, vib_width = 0.0;
  double mean_conf = 0.0;
  int frames = 0;                    // voiced frames in the note (before head/tail trimming)
};

class NoteSegmenter {
 public:
  static constexpr int kMaxRewind = 32;
  static constexpr double kGuardS = 0.030;  // guard zone after a note start / before a boundary
  static constexpr int kEndSkip = 3;    // release smear at the end of a run
  static constexpr int kNbFrames = 16;  // frames next to a boundary checked against the neighbouring note
  static constexpr int kRing = 48;      // >= kMaxRewind + kNbFrames

  // min_frames: shorter runs are discarded, and so is a note with no frame left for the pitch statistics.
  explicit NoteSegmenter(int min_frames) : min_(std::max(min_frames, 1)) {}

  // Appends a committed voiced frame to the current note (starting one if none is open).
  void add(const NoteFrame& f) {
    if (carry_n_ > 0) {  // frames rewound out of the previous note start the new one
      for (int i = 0; i < carry_n_; ++i) add_one(carry_[i]);
      carry_n_ = 0;
    }
    add_one(f);
  }

  // Ends the current note; the newest `rewind` frames go to the next note. True if a summary was written to `out`.
  // `t_b` is the boundary time: the old note ends no later than it and the new note starts at it.
  // `new_c` (cents re 440) is the semitone centre of the next note; omit it (NaN) for a split without a pitch change
  // (RMS onset): then no neighbour test is made.
  bool boundary(int rewind, NoteSummary& out, double t_b, double new_c = NAN) {
    if (!open_) return false;
    const bool nb = !std::isnan(new_c);
    const bool emitted = close(std::clamp(rewind, 0, kMaxRewind), out, true, nb, new_c, t_b);
    if (emitted) out.t_end = std::min(out.t_end, t_b);
    next_t0_ = t_b;
    has_next_t0_ = true;
    nb_valid_ = nb && emitted;      // the next note's head is tested against this note's measured mean
    prev_mean_ = out.mean_c;
    return emitted;
  }

  // Ends the current note with nothing carried over (end of a run).
  bool end(NoteSummary& out) {
    const bool emitted = open_ ? close(0, out, false, false, 0.0, 0.0) : false;
    nb_valid_ = false;               // after the close: the last note of a run still gets its head test
    return emitted;
  }

  int frames_in_note() const { return open_ ? a_.n_all : 0; }

 private:
  struct Acc {
    int n_all = 0;   // voiced frames in the note
    int n = 0;       // frames in the statistics
    int vib_n = 0;
    double ref = 0.0, s1 = 0.0, s2 = 0.0, conf = 0.0, vr = 0.0, vw = 0.0, t0 = 0.0, t1 = 0.0;
  };
  struct Slot {
    NoteFrame f;
    bool counted = false;
  };

  void include(const NoteFrame& f, double sign) {
    const double d = f.c - a_.ref;
    a_.n += static_cast<int>(sign);
    a_.s1 += sign * d;
    a_.s2 += sign * d * d;
    a_.conf += sign * f.conf;
    if (f.vr > 0.0) {
      a_.vib_n += static_cast<int>(sign);
      a_.vr += sign * f.vr;
      a_.vw += sign * f.vw;
    }
  }

  Slot& at_newest(int k) { return ring_[(head_ - 1 - k + 4 * kRing) % kRing]; }  // k = 0 is the newest

  void add_one(const NoteFrame& f) {
    if (!open_) {
      a_ = Acc{};
      a_.t0 = has_next_t0_ ? next_t0_ : f.t;
      has_next_t0_ = false;
      open_ = true;
      count_ = 0;
      ref_set_ = false;
    }
    if (!ref_set_) {  // the reference only keeps the sums small; any frame will do
      a_.ref = f.c;
      ref_set_ = true;
    }
    Slot& s = ring_[head_];
    s.f = f;
    s.counted = f.t >= a_.t0 + kGuardS;
    if (a_.n_all < kNbFrames) first_[a_.n_all] = {f, s.counted};
    if (s.counted) include(f, +1.0);
    head_ = (head_ + 1) % kRing;
    if (count_ < kRing) ++count_;
    ++a_.n_all;
    a_.t1 = f.t;
  }

  // Closes the open note, giving the newest `rewind` frames to the next one. Returns true if a note was emitted.
  bool close(int rewind, NoteSummary& out, bool at_boundary, bool nb, double new_c, double t_b) {
    rewind = std::min({rewind, count_, a_.n_all});
    carry_n_ = rewind;
    for (int i = 0; i < rewind; ++i) {  // carry oldest first
      Slot& s = at_newest(rewind - 1 - i);
      carry_[i] = s.f;
      if (s.counted) include(s.f, -1.0);
    }
    a_.n_all -= rewind;
    count_ -= rewind;
    head_ = (head_ - rewind + 2 * kRing) % kRing;
    if (rewind > 0 && count_ > 0) a_.t1 = at_newest(0).f.t;
    const double own0 = a_.n > 0 ? a_.ref + a_.s1 / a_.n : 0.0;   // measured mean before the tail trim
    for (int k = 0; k < kNbFrames && k < count_; ++k) {
      Slot& s = at_newest(k);
      const bool guard = at_boundary ? s.f.t > t_b - kGuardS : k < kEndSkip;   // 30 ms before a boundary / release trim at a run end
      const bool drop = guard || (nb && std::fabs(s.f.ctr - new_c) < std::fabs(s.f.ctr - own0));   // or centre nearer the next note
      if (s.counted && drop) {
        include(s.f, -1.0);
        s.counted = false;
      }
    }
    if (nb_valid_ && a_.n > 0) {       // head: centre nearer the previous note than this one (one refinement pass)
      const double own = a_.ref + a_.s1 / a_.n;
      for (int i = 0; i < kNbFrames && i < a_.n_all - kNbFrames; ++i) {   // not the frames the tail pass may have taken
        if (first_[i].counted && std::fabs(first_[i].f.ctr - prev_mean_) < std::fabs(first_[i].f.ctr - own)) {
          include(first_[i].f, -1.0);
          first_[i].counted = false;
        }
      }
    }
    open_ = false;
    count_ = 0;
    if (a_.n_all < min_ || a_.n < 1) return false;
    const double mean = a_.s1 / a_.n;
    out.t_start = a_.t0;
    out.t_end = a_.t1;
    out.mean_c = a_.ref + mean;
    out.std_c = std::sqrt(std::max(0.0, a_.s2 / a_.n - mean * mean));
    out.mean_conf = a_.conf / a_.n;
    out.frames = a_.n_all;
    // vibrato figures only if at least 30% of the frames in the statistics carried a vibrato reading
    const bool vib = a_.vib_n > 0 && a_.vib_n * 10 >= a_.n * 3;
    out.vib_rate = vib ? a_.vr / a_.vib_n : 0.0;
    out.vib_width = vib ? a_.vw / a_.vib_n : 0.0;
    return true;
  }

  int min_;
  bool open_ = false, ref_set_ = false, has_next_t0_ = false, nb_valid_ = false;
  double next_t0_ = 0.0, prev_mean_ = 0.0;
  Acc a_;
  struct HeadFrame {
    NoteFrame f;
    bool counted = false;
  };
  HeadFrame first_[kNbFrames];   // the first frames of the open note, kept for the head test at close
  Slot ring_[kRing];
  int head_ = 0, count_ = 0;
  NoteFrame carry_[kMaxRewind];
  int carry_n_ = 0;
};

}  // namespace intono
