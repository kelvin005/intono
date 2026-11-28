// Score cursor for scale mode (ADR 0014): where the player is in the expected sequence, and whether the note HMM may be biased towards
// it. Worker thread only (inline mode: the audio thread); no allocation, fixed storage.
//
//   biased:  a note == expected[k] advances k by one; == expected[k+1] (at most ONE missed note) by two; anything else is a miss.
//            3 consecutive misses drop the bias (plain, free-mode decoding).
//   plain:   2 consecutive notes matching expected[p], expected[p+1] for some p >= k restore the bias with k = p + 2.
//   pairs(): the steps expected[j-1] -> expected[j] for the next kAhead j from k (the decoder runs a fixed lag ahead of the emitted
//            notes, so the steps just ahead of the cursor are the ones it is deciding); none while plain.
#pragma once

namespace intono {

// ADR 0018: in scale mode a note whose mean is within this many cents (re the tuning's own target) of a due note is labelled as that note.
constexpr double kScaleLabelWindow = 60.0;

class ScoreCursor {
 public:
  static constexpr int kMax = 128;
  static constexpr int kAhead = 4;
  static constexpr int kMissLimit = 3;

  void set(const int* midi, int n) {
    n_ = (midi && n > 0) ? (n < kMax ? n : kMax) : 0;
    for (int i = 0; i < n_; ++i) seq_[i] = midi[i];
    k_ = 0;
    misses_ = 0;
    prev_ = -1;
    biased_ = n_ > 0;
  }

  bool biased() const { return biased_; }
  int k() const { return k_; }
  int misses() const { return misses_; }
  int size() const { return n_; }

  // The i-th note due from the cursor on (0 = expected[k]); -1 if none or free mode (plain).
  int due(int i) const { return biased_ && k_ + i < n_ ? seq_[k_ + i] : -1; }

  void on_note(int midi) {
    if (n_ == 0) return;
    if (biased_) {
      if (k_ < n_ && midi == seq_[k_]) {
        k_ += 1;
        misses_ = 0;
      } else if (k_ + 1 < n_ && midi == seq_[k_ + 1]) {
        k_ += 2;
        misses_ = 0;
      } else if (++misses_ >= kMissLimit) {
        biased_ = false;
      }
    } else if (prev_ >= 0) {
      for (int p = k_; p + 1 < n_; ++p)
        if (seq_[p] == prev_ && seq_[p + 1] == midi) {
          k_ = p + 2;
          misses_ = 0;
          biased_ = true;
          break;
        }
    }
    prev_ = midi;
  }

  // Writes up to kAhead (from, to) MIDI pairs; returns how many.
  int pairs(int* from, int* to) const {
    if (!biased_) return 0;
    int n = 0;
    for (int j = k_ > 0 ? k_ : 1; j < n_ && j < k_ + kAhead + (k_ == 0 ? 1 : 0) && n < kAhead; ++j)
      if (seq_[j - 1] != seq_[j]) {
        from[n] = seq_[j - 1];
        to[n] = seq_[j];
        ++n;
      }
    return n;
  }

 private:
  int seq_[kMax] = {};
  int n_ = 0, k_ = 0, misses_ = 0, prev_ = -1;
  bool biased_ = false;
};

}  // namespace intono
