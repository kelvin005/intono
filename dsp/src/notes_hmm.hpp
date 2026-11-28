// Note tracker (ADR 0004): finds note boundaries with a fixed-lag HMM on the raw pitch track, places each boundary
// with a sinusoid-plus-step change-point fit, and feeds the NoteSegmenter (notes.hpp) with committed frames.
//
//   * States: one per ET semitone, MIDI 52..102, centred on a4_hz. Observation: raw guarded pitch, cents re a4_hz.
//   * Emission cost: max(0, |c - centre| - 50) / 25, so vibrato up to +-50 cents costs nothing.
//   * Transition cost: 0 to stay, kHmmSwitch to go to any other state.
//   * Viterbi forward pass in O(states) per voiced frame; the frame kHmmLag voiced frames old is committed by
//     backtracking from the best current state. A run ends after more than `gap_frames` unvoiced frames; the
//     pending frames are then decoded from the best final state (flush).
//   * A label change proposed at frame k is placed by a change-point fit over the frames around it: each side of
//     the step is a constant, or a constant plus one sinusoid (3.5..9 Hz, amplitude <= 70 cents), chosen by BIC; the
//     smeared frames within half an analysis window of the step belong to neither side. The step time is the fit's
//     minimum. If the fitted levels (vibrato removed) differ by less than kFitMinStep, or the wrong way, the
//     proposal is vetoed: the note continues and the HMM state is adopted without a split. Amendment 4: the data of a
//     fit stop at the path's NEXT switch, so a window never holds two boundaries; a side shorter than kFitMinSide (24)
//     but at least kFitMinEdge (12) frames is allowed if the model of the other (long) side, extended over it, misses it
//     by kFitMinStep; if neither side is long, the HMM's own switch frame is kept (its medians must still differ by
//     kFitMinStep). A dwell of the path in another state shorter than kFitMinEdge frames is a glitch (an octave error
//     at the head of a note), not a note: it makes no proposal and its frames stay out of the next fit.
//     Octave-error frames at the start of a run and the last kEndSkip frames take no part in a fit.
//   * An RMS onset (from the engine) also starts a new note, acting when its frame is committed.
// Everything is a fixed array: no allocation, no locks, safe on the audio thread.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>

#include "notes.hpp"

namespace intono {

constexpr int kHmmStates = 51;
constexpr int kHmmMidiLo = 52;
constexpr int kHmmLag = 40;          // voiced frames (213 ms at 256/48000)
constexpr int kHmmRing = 256;        // >= kHmmLag + kHmmSearch + kFitBack + kFitSmear
constexpr int kHmmSearch = 24;       // the boundary may move this many frames back from the HMM's switch ...
constexpr int kHmmAhead = 24;        // ... or forward (the path can switch early when the old note's vibrato reaches the new state)
constexpr double kHmmTolerance = 50.0, kHmmSigma = 25.0, kHmmSwitch = 24.0;
// Scale mode (ADR 0014, Amendment 1): the cost of entering a note due next in the expected sequence. Chosen on dev seeds 9501-9516
// (short runs) and 9521-9536 (deviations) only, never on the sealed sets p3gate and p3dev: 4, 6 and 8 gave identical dev results;
// 8 is the weakest bias of that plateau. tools/accuracy/reports/phase3/score_informed_dev.md.
constexpr double kHmmSwitchExpected = 8.0;
constexpr int kHmmMaxBias = 4;
// Scale mode (ADR 0018): the cost-free zone of a semitone state is +-30 cents instead of +-50 while the decoder has steps to follow.
// With notes played 20 to 40 cents off their semitone the neighbouring +-50 zones overlap and a note 13 cents outside the old zone cost
// almost nothing there, so the path never switched (dev seeds 9561-9576, 60-80 cent steps: recall 0.891). 20, 30 and 40 gave 0.982, 0.982
// and 0.968; 30 is the weakest change of that plateau. Chosen on dev seeds only, never on the sealed sets.
constexpr double kHmmScaleTolerance = 30.0;

// change-point fit
constexpr int kFitOmegas = 12;       // vibrato rates 3.5, 4.0 ... 9.0 Hz
constexpr double kFitOmegaLo = 3.5, kFitOmegaStep = 0.5;
constexpr int kFitBack = 56;         // frames of each side used
constexpr int kFitMax = 136;         // window frames: kHmmSearch + kFitBack + kHmmLag + slack
constexpr int kFitMinSin = 12;       // frames a side needs for the sinusoid model
constexpr int kFitMinSide = 24;      // frames a side needs to stand on its own: half a 4 Hz vibrato cycle (128 ms); a
                                     // shorter side cannot tell a level from a vibrato swing, so it needs the extension test
constexpr double kFitAmpCap = 70.0;  // cents
constexpr double kFitFloor = 2.0;    // cents: noise floor in the BIC
constexpr double kFitTie = 12.0;      // BIC units
constexpr double kFitMinStep = 25.0; // cents: smaller fitted level change = not a note change
// run edges (ADR 0004 amendment): the first and last note of a run may be short (a tonic of 16th notes is 125 ms). A side
// that touches the start or the end of the run needs only kFitMinEdge frames, but then the model of the other (long)
// side, a constant or a sinusoid, extended over the short side must miss its frames by at least kFitMinStep (rms): a
// vibrato swing at the edge of a steady note is predicted by the sinusoid, a new note is not.
constexpr int kFitMinEdge = 12;
// The first frames of a run can be octave errors (YIN at the onset). Leading frames (among the first kFitLead) that are
// more than kFitGlitch cents from the median of the following kFitLead frames take no part in a fit.
constexpr int kFitLead = 8;
constexpr double kFitGlitch = 600.0;

class NoteTracker {
 public:
  static constexpr int kMaxOut = 8;  // summaries one update can produce (flush of a 41-frame window, 13-frame notes)

  // half_window_s: half an analysis window in seconds (1024 / 2 / 48000 = 10.7 ms). A frame whose window contains the
  // step is smeared; the fit leaves those frames out.
  NoteTracker(int gap_frames, int min_frames, double half_window_s)
      : gap_(gap_frames), seg_(min_frames), min_(min_frames), hw_(half_window_s) {}

  // Ends the open run now (ADR 0008: the record stream has a hole, so no frame may be carried across it). Same closing as the
  // end-of-run after a long gap. Returns the number of summaries written to out[0 .. kMaxOut).
  int flush(NoteSummary* out) {
    pending_rms_ = false;
    return open_ ? finish(out) : 0;
  }

  // Scale mode (ADR 0014): the steps just ahead of the cursor, as MIDI pairs (from, to); the decoder enters each `to` at
  // kHmmSwitchExpected instead of kHmmSwitch (Amendment 1: from any state; `from` is kept for the cursor's window and the tests)
  // on the ET grid of the HMM (state = midi - kHmmMidiLo). n = 0: free mode, the decoding is exactly the unbiased one. Pairs outside
  // the grid are ignored. Takes effect from the next frame.
  void set_bias(const int* from_midi, const int* to_midi, int n) {
    nb_ = 0;
    for (int i = 0; i < n && nb_ < kHmmMaxBias; ++i) {
      const int a = from_midi[i] - kHmmMidiLo, b = to_midi[i] - kHmmMidiLo;
      if (a >= 0 && a < kHmmStates && b >= 0 && b < kHmmStates && a != b) {
        bias_from_[nb_] = a;
        bias_to_[nb_] = b;
        ++nb_;
      }
    }
  }

  // One call per hop. `f.c` (cents re 440 Hz) feeds the note statistics; `cents_a4` (cents re a4_hz) feeds the HMM grid.
  // Returns the number of summaries written to out[0 .. kMaxOut).
  int update(bool voiced, bool rms_onset, const NoteFrame& f, double cents_a4, NoteSummary* out) {
    int n_out = 0;
    if (!voiced) {
      if (rms_onset) pending_rms_ = true;
      if (open_ && ++unvoiced_ > gap_) n_out = finish(out);
      return n_out;
    }
    unvoiced_ = 0;
    if (!open_) start_run();
    Slot& sl = ring_[n_ & (kHmmRing - 1)];
    sl.f = f;
    sl.c = cents_a4;
    sl.rms = rms_onset || pending_rms_;
    pending_rms_ = false;
    forward(cents_a4);
    ++n_;
    if (n_ - 1 >= kHmmLag) {                 // frame index (n_-1) - kHmmLag becomes final
      const int k = n_ - 1 - kHmmLag;
      n_out += commit(k, label_at(n_ - 1, k), n_ - 1, out + n_out);
      committed_ = k + 1;
    }
    return n_out;
  }

 private:
  struct Slot {
    NoteFrame f;
    double c = 0.0;
    bool rms = false;
  };

  void start_run() {
    open_ = true;
    n_ = 0;
    committed_ = 0;
    label_prev_ = -1;
    note_start_ = 0;
    next_add_ = 0;
    unvoiced_ = 0;
    skip_until_ = 0;
    hole_lo_ = -1;
  }

  void forward(double c) {
    double e[kHmmStates];
    const double tol = nb_ > 0 ? kHmmScaleTolerance : kHmmTolerance;   // free mode (nb_ == 0): unchanged
    for (int s = 0; s < kHmmStates; ++s) {
      const double centre = 100.0 * (kHmmMidiLo + s - 69);
      e[s] = std::max(0.0, std::fabs(c - centre) - tol) / kHmmSigma;
    }
    const int t = n_ & (kHmmRing - 1);
    if (n_ == 0) {
      for (int s = 0; s < kHmmStates; ++s) delta_[s] = e[s];
    } else {
      double m = delta_[0];
      int am = 0;
      for (int s = 1; s < kHmmStates; ++s)
        if (delta_[s] < m) {
          m = delta_[s];
          am = s;
        }
      prev_best_[t] = static_cast<uint8_t>(am);
      has_via_[t] = 0;
      const double sw = m + kHmmSwitch;
      for (int s = 0; s < kHmmStates; ++s) {
        if (delta_[s] <= sw) {
          delta_[s] = e[s] + delta_[s];
          stay_[t][s] = 1;
        } else {
          delta_[s] = e[s] + sw;
          stay_[t][s] = 0;
        }
      }
      // Scale mode: the notes due next (the targets of the cursor's pairs) may be entered at the lower cost, from whatever state the
      // best path is in, so a note the player inserts before the due one costs what it costs in free mode (ADR 0014 Amendment 1:
      // a cheap step only from expected[k-1] swallowed off-scale insertions on the dev seeds). Applied after the unbiased update,
      // only where it is cheaper; the frame remembers where the entry came from (via_) for the backtrace. Free mode never gets here.
      if (nb_ > 0) {
        has_via_[t] = 1;
        for (int s = 0; s < kHmmStates; ++s) via_[t][s] = 0;
        for (int q = 0; q < nb_; ++q) {
          const int b = bias_to_[q];
          const double cheap = e[b] + m + kHmmSwitchExpected;   // entry into the due note from the best state (ADR 0014 Amendment 1)
          if (cheap < delta_[b]) {
            delta_[b] = cheap;
            stay_[t][b] = 0;
            via_[t][b] = static_cast<uint8_t>(am + 1);
          }
        }
      }
    }
    double lo = delta_[0];
    for (int s = 1; s < kHmmStates; ++s) lo = std::min(lo, delta_[s]);
    for (int s = 0; s < kHmmStates; ++s) delta_[s] -= lo;   // keep the scores small
  }

  // The state at frame t-1 on the path that is in state s at frame t (i = t's ring index).
  int back(int i, int s) const {
    if (stay_[i][s]) return s;
    if (has_via_[i] && via_[i][s]) return via_[i][s] - 1;
    return prev_best_[i];
  }

  int best_state() const {
    int b = 0;
    for (int s = 1; s < kHmmStates; ++s)
      if (delta_[s] < delta_[b]) b = s;
    return b;
  }

  // State of frame k on the best path ending at frame `last`.
  int label_at(int last, int k) const {
    int s = best_state();
    for (int t = last; t > k; --t) {
      const int i = t & (kHmmRing - 1);
      s = back(i, s);
    }
    return s;
  }

  // First frame after k whose state on the best path ending at `last` differs from the state at k, or -1 if the path
  // does not switch again up to `last`. It is the anchor of the NEXT boundary: no fit window reaches past it.
  int next_switch(int last, int k) const {
    int s = best_state();
    int found = -1;
    int sk = -1;
    // walk back from `last`, remembering the earliest frame (> k) whose state differs from the state at k
    int st[kHmmLag + 2 * kHmmSearch];
    const int span = std::min(last - k + 1, kHmmLag + 2 * kHmmSearch);
    for (int t = last; t >= last - span + 1; --t) {
      st[t - (last - span + 1)] = s;
      const int i = t & (kHmmRing - 1);
      s = back(i, s);
    }
    const int base = last - span + 1;
    sk = k >= base ? st[k - base] : -1;
    if (sk < 0) return -1;
    for (int t = k + 1; t <= last; ++t)
      if (st[t - base] != sk) { found = t; break; }
    return found;
  }

  // ---- change-point fit -------------------------------------------------------------------------------------------
  struct Side {
    double j = 0.0;      // BIC cost, zero for a perfect fit (so sides with different frame counts compare)
    double level = 0.0;  // fitted constant, cents re a4 relative to the window reference
    int w = -1;          // rate index of the winning sinusoid model, -1 for the constant model
    double am = 0.0, bm = 0.0;   // its sine and cosine coefficients (level is its constant)
  };
  struct Fit {
    bool valid = false;
    int idx = 0;         // ring index of the first frame of the new note
    double t = 0.0;      // step time, seconds
    double step = 0.0;   // fitted level change, cents (new - old)
  };

  // Best of constant / constant + sinusoid for window frames [lo, hi).
  Side fit_side(int lo, int hi) const {
    const int n = hi - lo;
    const double sy = py_[hi] - py_[lo], syy = pyy_[hi] - pyy_[lo];
    const double dn = static_cast<double>(n);
    Side best;
    best.level = sy / dn;
    const double rss0 = std::max(0.0, syy - sy * sy / dn);
    best.j = dn * std::log1p(rss0 / (dn * kFitFloor * kFitFloor)) + std::log(dn);
    if (n < kFitMinSin) return best;
    const double pen3 = 3.0 * std::log(dn);
    for (int w = 0; w < kFitOmegas; ++w) {
      const double* a = pre_[w][hi];
      const double* b = pre_[w][lo];
      const double ss = a[0] - b[0], sc = a[1] - b[1], cc = a[2] - b[2], s1 = a[3] - b[3], c1 = a[4] - b[4];
      const double ys = a[5] - b[5], yc = a[6] - b[6];
      // normal equations [[n s1 c1] [s1 ss sc] [c1 sc cc]] [m a b]' = [sy ys yc]'  (Cramer's rule)
      const double d00 = ss * cc - sc * sc, d01 = s1 * cc - sc * c1, d02 = s1 * sc - ss * c1;
      const double det = dn * d00 - s1 * d01 + c1 * d02;
      if (std::fabs(det) < 1e-9 * dn * dn * dn) continue;
      const double m = (sy * d00 - s1 * (ys * cc - sc * yc) + c1 * (ys * sc - ss * yc)) / det;
      const double am = (dn * (ys * cc - sc * yc) - sy * d01 + c1 * (s1 * yc - ys * c1)) / det;
      const double bm = (dn * (ss * yc - ys * sc) - s1 * (s1 * yc - ys * c1) + sy * d02) / det;
      if (am * am + bm * bm > kFitAmpCap * kFitAmpCap) continue;
      const double rss = std::max(0.0, syy - (m * sy + am * ys + bm * yc));
      const double j = dn * std::log1p(rss / (dn * kFitFloor * kFitFloor)) + pen3;
      if (j < best.j) {
        best.j = j;
        best.level = m;
        best.w = w;
        best.am = am;
        best.bm = bm;
      }
    }
    return best;
  }

  // Root-mean-square miss of window frames [lo, hi) against the model of another side extended over them.
  double extend_rmse(const Side& s, int lo, int hi) const {
    double ss = 0.0;
    const double om = s.w >= 0 ? 2.0 * 3.14159265358979323846 * (kFitOmegaLo + kFitOmegaStep * s.w) : 0.0;
    for (int i = lo; i < hi; ++i) {
      double pred = s.level;
      if (s.w >= 0) pred += s.am * std::sin(om * tt_[i]) + s.bm * std::cos(om * tt_[i]);
      const double e = (py_[i + 1] - py_[i]) - pred;
      ss += e * e;
    }
    return std::sqrt(ss / static_cast<double>(hi - lo));
  }

  // Places a label change proposed at frame k (newest frame `last`).
  // at_end: `last` is the final frame of the run (flush), so the right side may be as short as kFitMinEdge.
  Fit change_point(int k, int last_frame, bool at_end, int hole_lo = -1) {
    Fit r;
    // hole_lo >= 0: frames [hole_lo, k) are a transient (an octave-error dwell of the path, shorter than kFitMinEdge) at the
    // head of the new note: the boundary is anchored at hole_lo and the right side starts at k.
    const int kk = hole_lo >= 0 ? hole_lo : k;
    // The last frames of a run are where YIN fails as the note dies away (one stray frame can drag the Viterbi path to
    // the lowest state): they take no part in a fit and cannot propose a boundary, as the segmenter trims them from
    // the statistics anyway.
    int last = at_end ? last_frame - NoteSegmenter::kEndSkip : last_frame;
    // Amendment 4: the next boundary's anchor (the HMM's next switch on the path) bounds the data of this fit, so a
    // window never holds two boundaries. The smoothed path switches at the step itself (it is decoded backwards), so no
    // margin is kept.
    const int kn = next_switch(last_frame, k);
    if (kn > 0) last = std::min(last, kn - 1);
    if (k > last) return r;
    // A side needs kFitMinEdge frames at least; one shorter than kFitMinSide is accepted only if the other side's model,
    // extended over it, misses it by kFitMinStep (below). If no candidate has a long side, the HMM's own switch frame
    // is kept (fallback below).
    const int min_l = kFitMinEdge;
    const int min_r = kFitMinEdge;
    const int jlo = std::max({kk - kHmmSearch, note_start_ + min_, 1});
    const int jhi = std::min(k + kHmmAhead, last - (min_r + 3));
    int i0 = std::max({note_start_ + 3, kk - kHmmSearch - kFitBack, last - (kFitMax - 1)});
    if (note_start_ == 0 && last >= 2 * kFitLead - 1 && last < kHmmRing) {   // glitch frames at the start of the run
      double v[kFitLead];
      for (int i = 0; i < kFitLead; ++i) v[i] = ring_[kFitLead + i].c;
      std::sort(v, v + kFitLead);
      const double ref = 0.5 * (v[kFitLead / 2 - 1] + v[kFitLead / 2]);
      for (int i = 0; i < kFitLead; ++i)
        if (std::fabs(ring_[i].c - ref) > kFitGlitch) i0 = std::max(i0, i + 1);
    }
    // No long side to fit from (two short notes side by side): keep the HMM's own switch frame (it is decoded backwards,
    // so it sits on the step) instead of searching for a better one among candidates that would each have one polluted side.
    // A transient at the head of the new note (octave-error dwell): the dwell starts at the step, the path's switch frame is
    // that frame, and the frames between it and the right side carry no information (the cost over them is flat except for
    // the drift of the old note, which would pull the boundary back): keep the HMM's frame.
    if (hole_lo >= 0) return fallback(kk, k, i0, last);
    if (kk - i0 < kFitMinSide && last - k + 1 < kFitMinSide) return fallback(kk, k, i0, last);
    const int m = last - i0 + 1;
    const double t0 = ring_[kk & (kHmmRing - 1)].f.t, y0 = ring_[kk & (kHmmRing - 1)].c;
    for (int w = 0; w < kFitOmegas; ++w)
      for (int q = 0; q < 7; ++q) pre_[w][0][q] = 0.0;
    py_[0] = pyy_[0] = 0.0;
    for (int i = 0; i < m; ++i) {
      const Slot& sl = ring_[(i0 + i) & (kHmmRing - 1)];
      const double t = sl.f.t - t0, y = sl.c - y0;
      tt_[i] = t;
      py_[i + 1] = py_[i] + y;
      pyy_[i + 1] = pyy_[i] + y * y;
      for (int w = 0; w < kFitOmegas; ++w) {
        const double ph = 2.0 * 3.14159265358979323846 * (kFitOmegaLo + kFitOmegaStep * w) * t;
        const double s = std::sin(ph), c = std::cos(ph);
        const double* p = pre_[w][i];
        double* q = pre_[w][i + 1];
        q[0] = p[0] + s * s;
        q[1] = p[1] + s * c;
        q[2] = p[2] + c * c;
        q[3] = p[3] + s;
        q[4] = p[4] + c;
        q[5] = p[5] + y * s;
        q[6] = p[6] + y * c;
      }
    }
    double best = 1e300;
    int n_cand = 0;
    bool both_short = false, ext_rejected = false;   // why candidates were dropped (decides the fallback)
    for (int j = jlo; j <= jhi; ++j) {
      const int mj = j - i0;
      if (mj < 1) continue;
      const double tau = 0.5 * (tt_[mj - 1] + tt_[mj]);
      int il = mj;                                     // left: frames with t < tau - hw
      while (il > 0 && tt_[il - 1] >= tau - hw_) --il;
      int ir = mj;                                     // right: frames with t > tau + hw
      while (ir < m && tt_[ir] <= tau + hw_) ++ir;
      const int ll = std::max(0, il - kFitBack), rh = std::min(m, ir + kFitBack);
      if (il - ll < min_l || rh - ir < min_r) continue;
      const Side a = fit_side(ll, il), b = fit_side(ir, rh);
      const double jt = a.j + b.j;
      const bool short_l = il - ll < kFitMinSide, short_r = rh - ir < kFitMinSide;
      if (short_l && short_r) { both_short = true; continue; }  // no long side to predict from
      if (short_l || short_r) {                                // a short edge side: the long side's model must not explain it
        const double miss = short_l ? extend_rmse(b, ll, il) : extend_rmse(a, ir, rh);
        if (miss < kFitMinStep) { ext_rejected = true; continue; }
      }
      cand_j_[n_cand] = jt;
      cand_i_[n_cand] = j;
      cand_t_[n_cand] = t0 + tau;
      cand_s_[n_cand] = b.level - a.level;
      ++n_cand;
      best = std::min(best, jt);
    }
    // The anchors' sides were long enough, but once the smeared frames are taken out every candidate has two short sides:
    // keep the HMM's frame as well. If the extension test rejected any candidate the step is not there: no boundary.
    if (n_cand == 0) return both_short && !ext_rejected ? fallback(kk, k, i0, last) : r;
    // The cost is flat over every position whose excluded frames cover the smeared step: the step is somewhere on
    // that plateau. Take the contiguous run of candidates around the minimum with cost within kFitTie of it and
    // put the step at the middle of the run in TIME (frame positions are not evenly spaced across dropouts).
    int amin = 0;
    for (int c = 1; c < n_cand; ++c)
      if (cand_j_[c] < cand_j_[amin]) amin = c;
    int c0 = amin, c1 = amin;
    while (c0 > 0 && cand_j_[c0 - 1] <= best + kFitTie) --c0;
    while (c1 + 1 < n_cand && cand_j_[c1 + 1] <= best + kFitTie) ++c1;
    const double t_mid = 0.5 * (cand_t_[c0] + cand_t_[c1]);
    int pick = c0;
    for (int c = c0; c <= c1; ++c)
      if (std::fabs(cand_t_[c] - t_mid) < std::fabs(cand_t_[pick] - t_mid)) pick = c;
    r.valid = true;
    r.idx = cand_i_[pick];
    r.t = t_mid;
    r.step = cand_s_[pick];
    return r;
  }

  // No candidate had a long side (two short notes side by side, or a window cut short by the next anchor): keep the HMM's
  // own switch frame k, provided the medians of the frames on each side (inside the bounded window) differ by at least
  // kFitMinStep in the direction of the change; commit() applies the sign test.
  Fit fallback(int kk, int k, int i0, int last) const {
    Fit r;
    const int lo_l = std::max(i0, note_start_ + 3), hi_l = kk;          // [lo_l, hi_l)
    const int lo_r = k, hi_r = last + 1;                                // [lo_r, hi_r)
    const int nl = hi_l - lo_l, nr = hi_r - lo_r;
    if (nl < kFitMinEdge || nr < kFitMinEdge) return r;
    r.valid = true;
    r.idx = kk;
    r.t = 0.5 * (ring_[(kk - 1) & (kHmmRing - 1)].f.t + ring_[kk & (kHmmRing - 1)].f.t);
    r.step = median_c(lo_r, hi_r) - median_c(lo_l, hi_l);
    return r;
  }
  double median_c(int lo, int hi) const {
    double v[kFitMax];
    int n = 0;
    for (int i = lo; i < hi && n < kFitMax; ++i) v[n++] = ring_[i & (kHmmRing - 1)].c;
    std::sort(v, v + n);
    return n & 1 ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2]);
  }

  // Frame k is final with state `label`; `last` is the newest frame in the run.
  int commit(int k, int label, int last, NoteSummary* out, bool at_end = false) {
    if (k < next_add_) return 0;   // a look-ahead boundary already placed this frame in the old note
    int n_out = 0;
    const Slot& sl = ring_[k & (kHmmRing - 1)];
    bool split = false;
    if (hole_lo_ >= 0 && k >= skip_until_ && label == label_prev_) hole_lo_ = -1;   // the path came back to the same note
    if (label_prev_ >= 0 && label != label_prev_ && k < skip_until_) {
      // inside a transient dwell: no proposal (see below); the frame stays in the old note for now
    } else if (label_prev_ >= 0 && label != label_prev_) {
      // A dwell of the path in another state that lasts fewer than kFitMinEdge frames before the next switch is not a note
      // (shorter than the 10-frame minimum anyway): it is an octave-error glitch at the head of the next note, or of a
      // return to the same note. No proposal now; the next switch is compared with the note before the dwell, and
      // the dwell frames are left out of the fit.
      const int kn = next_switch(last, k);
      if (kn > 0 && kn - k < kFitMinEdge) {
        skip_until_ = kn;
        if (hole_lo_ < 0) hole_lo_ = k;
      } else {
        const int sign = label > label_prev_ ? 1 : -1;
        const Fit fit = change_point(k, last, at_end, hole_lo_);
        hole_lo_ = -1;
        // no valid fit: no boundary, the note keeps the new state
        if (fit.valid && sign * fit.step >= kFitMinStep) {
          split = true;
          place(fit.idx, fit.t, label, k, out, n_out);
        }
      }
    }
    if (!split) {
      if (sl.rms && label_prev_ >= 0) {
        if (seg_.boundary(0, out[n_out], sl.f.t)) ++n_out;
        note_start_ = k;
      }
      seg_.add(sl.f);
      next_add_ = k + 1;
    }
    if (!(k < skip_until_ || (hole_lo_ >= 0 && label != label_prev_))) label_prev_ = label;
    return n_out;
  }

  // The new note starts at ring frame `tau` / time `t_b`; frame k is the newest one committed.
  void place(int tau, double t_b, int label, int k, NoteSummary* out, int& n_out) {
    for (int j = next_add_; j < tau; ++j) seg_.add(ring_[j & (kHmmRing - 1)].f);   // frames the old note keeps
    const double off = ring_[k & (kHmmRing - 1)].f.c - ring_[k & (kHmmRing - 1)].c;   // cents re 440 minus cents re a4
    const double new_c = 100.0 * (kHmmMidiLo + label - 69) + off;
    if (seg_.boundary(std::max(0, next_add_ - tau), out[n_out], t_b, new_c)) ++n_out;
    note_start_ = tau;
    for (int j = std::max(tau, next_add_); j <= k; ++j) seg_.add(ring_[j & (kHmmRing - 1)].f);   // frames of the new note
    next_add_ = std::max(tau, k + 1);
  }

  // End of a run: decode every pending frame from the best final state, then close the last note.
  int finish(NoteSummary* out) {
    int n_out = 0;
    const int last = n_ - 1;
    if (committed_ <= last) {
      int labels[kHmmLag + 1];
      int s = best_state();
      for (int t = last; t >= committed_; --t) {
        labels[t - committed_] = s;
        const int i = t & (kHmmRing - 1);
        s = back(i, s);
      }
      for (int k = committed_; k <= last; ++k) n_out += commit(k, labels[k - committed_], last, out + n_out, true);
    }
    if (seg_.end(out[n_out])) ++n_out;
    open_ = false;
    pending_rms_ = false;
    return n_out;
  }

  int gap_;
  NoteSegmenter seg_;
  int min_;
  double hw_;
  bool open_ = false, pending_rms_ = false;
  int n_ = 0, committed_ = 0, label_prev_ = -1, note_start_ = 0, next_add_ = 0, unvoiced_ = 0;
  int skip_until_ = 0, hole_lo_ = -1;   // a transient dwell of the path: its switch frames are not proposals (commit)
  double delta_[kHmmStates] = {};
  uint8_t stay_[kHmmRing][kHmmStates] = {};
  uint8_t prev_best_[kHmmRing] = {};
  // scale mode (ADR 0014)
  int nb_ = 0, bias_from_[kHmmMaxBias] = {}, bias_to_[kHmmMaxBias] = {};
  uint8_t has_via_[kHmmRing] = {};
  uint8_t via_[kHmmRing][kHmmStates] = {};   // 1 + the state a cheap step came from, 0 = none
  Slot ring_[kHmmRing];
  // change-point fit scratch (preallocated)
  double pre_[kFitOmegas][kFitMax + 1][7] = {};
  double py_[kFitMax + 1] = {}, pyy_[kFitMax + 1] = {}, tt_[kFitMax] = {};
  static constexpr int kMaxCand = kHmmSearch + kHmmAhead + 1;
  double cand_j_[kMaxCand] = {}, cand_t_[kMaxCand] = {}, cand_s_[kMaxCand] = {};
  int cand_i_[kMaxCand] = {};
};

}  // namespace intono
