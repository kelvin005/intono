"""Streaming layer of libintono mirrored in Python: onset flag, tuning targets and note segmentation.

yin_ref.analyse() reproduces the per-frame pipeline up to the displayed pitch (gate, YIN, octave guard, ADR 0001
centre tracker). This module adds what engine.cpp does after that, line for line (ADR 0002 onsets, ADR 0003/0004
notes), so the C++ output can be compared frame by frame and note by note.

The note part mirrors dsp/src/notes.hpp (NoteSegmenter, robust statistics) and dsp/src/notes_hmm.hpp (NoteTracker:
fixed-lag note HMM + sinusoid-plus-step change-point fit). Same constants, same tie rules, same operation order.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np

import yin_ref

ONSET_RISE_DB = 6.0
ONSET_REFRACTORY = 10
PITCH_MOVE_C = 50.0
PITCH_MOVE_FRAMES = 6
RESUME_GAP_FRAMES = 20
NOTE_END_GAP = RESUME_GAP_FRAMES
NOTE_MIN_FRAMES = 10
STEP_SPAN_C = 50.0
STEP_SETTLED_C = 15.0
STEP_SPAN_FRAMES = 4

# NoteSegmenter (notes.hpp)
MAX_REWIND = 32
GUARD_S = 0.030
END_SKIP = 3
NB_FRAMES = 16
SEG_RING = 48

# NoteTracker (notes_hmm.hpp)
HMM_STATES = 51
HMM_MIDI_LO = 52
HMM_LAG = 40
HMM_SEARCH = 24
HMM_AHEAD = 24
HMM_TOLERANCE, HMM_SIGMA, HMM_SWITCH = 50.0, 25.0, 24.0
FIT_OMEGAS = 12
FIT_OMEGA_LO, FIT_OMEGA_STEP = 3.5, 0.5
FIT_BACK = 56
FIT_MAX = 136
FIT_MIN_SIN = 12
FIT_MIN_SIDE = 24
FIT_AMP_CAP = 70.0
FIT_FLOOR = 2.0
FIT_TIE = 12.0
FIT_MIN_STEP = 25.0
FIT_LEAD, FIT_GLITCH = 8, 600.0   # leading octave-error frames of a run take no part in a fit
FIT_MIN_EDGE = 12     # frames a side needs at the start or end of a run (the other side must predict it badly)
TWO_PI = 2.0 * 3.14159265358979323846

JUST = [1, 16 / 15, 9 / 8, 6 / 5, 5 / 4, 4 / 3, 45 / 32, 3 / 2, 8 / 5, 5 / 3, 9 / 5, 15 / 8]
PYTHAG = [1, 256 / 243, 9 / 8, 32 / 27, 81 / 64, 4 / 3, 729 / 512, 3 / 2, 128 / 81, 27 / 16, 16 / 9, 243 / 128]


def midi_to_hz(m, a4=440.0):
    return a4 * 2 ** ((m - 69.0) / 12.0)


def nearest_target(hz, tuning=0, a4=440.0, tonic=60):
    """Returns (target_hz, midi_note, cents). tuning 0 ET, 1 just, 2 pythagorean."""
    if not hz > 0:
        return 0.0, 0, 0.0
    if tuning == 0:
        x = 69.0 + 12.0 * np.log2(hz / a4)
        m = int(np.sign(x) * np.floor(abs(x) + 0.5))                 # std::lround: halves away from zero
        t = midi_to_hz(m, a4)
        return t, m, 1200 * np.log2(hz / t)
    ratios = JUST if tuning == 1 else PYTHAG
    f_t = midi_to_hz(tonic, a4)
    o0 = int(np.floor(np.log2(hz / f_t)))
    best, bf = 1e30, 0.0
    for o in range(o0 - 1, o0 + 2):
        for k in range(12):
            f = f_t * ratios[k] * 2.0**o
            c = 1200 * np.log2(hz / f)
            if abs(c) < abs(best):
                best, bf = c, f
    return bf, int(np.floor(69.0 + 12.0 * np.log2(bf / a4) + 0.5)), best


@dataclass
class Note:
    t_start: float
    t_end: float
    midi_note: int
    mean_cents: float
    std_cents: float
    vib_rate: float
    vib_width: float
    mean_conf: float
    frames: int


@dataclass
class NoteFrame:
    t: float = 0.0
    c: float = 0.0       # raw pitch, cents re 440
    conf: float = 0.0
    vr: float = 0.0
    vw: float = 0.0
    ctr: float = 0.0     # displayed vibrato centre, cents re 440


class _Acc:
    def __init__(self):
        self.n_all = self.n = self.vib_n = 0
        self.ref = self.s1 = self.s2 = self.conf = self.vr = self.vw = self.t0 = self.t1 = 0.0


class NoteSegmenter:
    """Mirror of dsp/src/notes.hpp."""

    def __init__(self, min_frames):
        self.min = max(min_frames, 1)
        self.open = self.ref_set = self.has_next_t0 = self.nb_valid = False
        self.next_t0 = self.prev_mean = 0.0
        self.a = _Acc()
        self.ring = [[None, False] for _ in range(SEG_RING)]      # [frame, counted]
        self.first = [[None, False] for _ in range(NB_FRAMES)]
        self.head = self.count = 0
        self.carry: list[NoteFrame] = []

    def add(self, f):
        if self.carry:
            for cf in self.carry:
                self._add_one(cf)
            self.carry = []
        self._add_one(f)

    def boundary(self, rewind, t_b, new_c=None):
        """Returns the summary dict of the closed note, or None."""
        if not self.open:
            return None
        nb = new_c is not None
        out = self._close(min(max(rewind, 0), MAX_REWIND), True, nb, new_c if nb else 0.0, t_b)
        if out is not None:
            out["t_end"] = min(out["t_end"], t_b)
        self.next_t0 = t_b
        self.has_next_t0 = True
        self.nb_valid = nb and out is not None
        if out is not None:
            self.prev_mean = out["mean_c"]
        return out

    def end(self):
        out = self._close(0, False, False, 0.0, 0.0) if self.open else None
        self.nb_valid = False
        return out

    def _include(self, f, sign):
        a = self.a
        d = f.c - a.ref
        a.n += int(sign)
        a.s1 += sign * d
        a.s2 += sign * d * d
        a.conf += sign * f.conf
        if f.vr > 0.0:
            a.vib_n += int(sign)
            a.vr += sign * f.vr
            a.vw += sign * f.vw

    def _at_newest(self, k):
        return self.ring[(self.head - 1 - k + 4 * SEG_RING) % SEG_RING]

    def _add_one(self, f):
        if not self.open:
            self.a = _Acc()
            self.a.t0 = self.next_t0 if self.has_next_t0 else f.t
            self.has_next_t0 = False
            self.open = True
            self.count = 0
            self.ref_set = False
        a = self.a
        if not self.ref_set:
            a.ref = f.c
            self.ref_set = True
        s = self.ring[self.head]
        s[0] = f
        s[1] = f.t >= a.t0 + GUARD_S
        if a.n_all < NB_FRAMES:
            self.first[a.n_all] = [f, s[1]]
        if s[1]:
            self._include(f, 1.0)
        self.head = (self.head + 1) % SEG_RING
        if self.count < SEG_RING:
            self.count += 1
        a.n_all += 1
        a.t1 = f.t

    def _close(self, rewind, at_boundary, nb, new_c, t_b):
        a = self.a
        rewind = min(rewind, self.count, a.n_all)
        self.carry = []
        for i in range(rewind):                                   # carry oldest first
            s = self._at_newest(rewind - 1 - i)
            self.carry.append(s[0])
            if s[1]:
                self._include(s[0], -1.0)
        a.n_all -= rewind
        self.count -= rewind
        self.head = (self.head - rewind + 2 * SEG_RING) % SEG_RING
        if rewind > 0 and self.count > 0:
            a.t1 = self._at_newest(0)[0].t
        own0 = a.ref + a.s1 / a.n if a.n > 0 else 0.0
        for k in range(min(NB_FRAMES, self.count)):
            s = self._at_newest(k)
            f = s[0]
            guard = (f.t > t_b - GUARD_S) if at_boundary else k < END_SKIP
            drop = guard or (nb and abs(f.ctr - new_c) < abs(f.ctr - own0))
            if s[1] and drop:
                self._include(f, -1.0)
                s[1] = False
        if self.nb_valid and a.n > 0:
            own = a.ref + a.s1 / a.n
            i = 0
            while i < NB_FRAMES and i < a.n_all - NB_FRAMES:
                fr, counted = self.first[i]
                if counted and abs(fr.ctr - self.prev_mean) < abs(fr.ctr - own):
                    self._include(fr, -1.0)
                    self.first[i][1] = False
                i += 1
        self.open = False
        self.count = 0
        if a.n_all < self.min or a.n < 1:
            return None
        mean = a.s1 / a.n
        vib = a.vib_n > 0 and a.vib_n * 10 >= a.n * 3
        return dict(t_start=a.t0, t_end=a.t1, mean_c=a.ref + mean,
                    std_c=math.sqrt(max(0.0, a.s2 / a.n - mean * mean)), mean_conf=a.conf / a.n, frames=a.n_all,
                    vib_rate=a.vr / a.vib_n if vib else 0.0, vib_width=a.vw / a.vib_n if vib else 0.0)


class NoteTracker:
    """Mirror of dsp/src/notes_hmm.hpp. The ring is unbounded here (frame indices of the run); the C++ ring is a
    power-of-two window that is never read further back than this one."""

    def __init__(self, gap_frames, min_frames, half_window_s):
        self.gap, self.min, self.hw = gap_frames, min_frames, half_window_s
        self.seg = NoteSegmenter(min_frames)
        self.open = self.pending_rms = False
        self.unvoiced = 0
        self._start_run()
        self.open = False

    def _start_run(self):
        self.open = True
        self.n = self.committed = 0
        self.label_prev = -1
        self.note_start = self.next_add = 0
        self.unvoiced = 0
        self.skip_until = 0
        self.hole_lo = -1
        self.ring: list = []          # (NoteFrame, cents_a4, rms)
        self.stay: list = []
        self.prev_best: list = []
        self.delta = [0.0] * HMM_STATES

    def update(self, voiced, rms_onset, f, cents_a4):
        out = []
        if not voiced:
            if rms_onset:
                self.pending_rms = True
            if self.open:
                self.unvoiced += 1
                if self.unvoiced > self.gap:
                    out = self._finish()
            return out
        self.unvoiced = 0
        if not self.open:
            self._start_run()
        self.ring.append((f, cents_a4, rms_onset or self.pending_rms))
        self.pending_rms = False
        self._forward(cents_a4)
        self.n += 1
        if self.n - 1 >= HMM_LAG:
            k = self.n - 1 - HMM_LAG
            out += self._commit(k, self._label_at(self.n - 1, k), self.n - 1)
            self.committed = k + 1
        return out

    def _forward(self, c):
        e = [max(0.0, abs(c - 100.0 * (HMM_MIDI_LO + s - 69)) - HMM_TOLERANCE) / HMM_SIGMA for s in range(HMM_STATES)]
        d = self.delta
        if self.n == 0:
            self.delta = list(e)
            self.stay.append([0] * HMM_STATES)
            self.prev_best.append(0)
        else:
            m, am = d[0], 0
            for s in range(1, HMM_STATES):
                if d[s] < m:
                    m, am = d[s], s
            self.prev_best.append(am)
            sw = m + HMM_SWITCH
            st = [0] * HMM_STATES
            nd = [0.0] * HMM_STATES
            for s in range(HMM_STATES):
                if d[s] <= sw:
                    nd[s] = e[s] + d[s]
                    st[s] = 1
                else:
                    nd[s] = e[s] + sw
            self.delta = nd
            self.stay.append(st)
        lo = min(self.delta)
        self.delta = [x - lo for x in self.delta]

    def _best_state(self):
        b = 0
        for s in range(1, HMM_STATES):
            if self.delta[s] < self.delta[b]:
                b = s
        return b

    def _label_at(self, last, k):
        s = self._best_state()
        for t in range(last, k, -1):
            if not self.stay[t][s]:
                s = self.prev_best[t]
        return s

    def _next_switch(self, last, k):
        """First frame after k whose state on the best path ending at `last` differs from the state at k, or -1."""
        s = self._best_state()
        span = min(last - k + 1, HMM_LAG + 2 * HMM_SEARCH)
        base = last - span + 1
        st = [0] * span
        for t in range(last, base - 1, -1):
            st[t - base] = s
            if not self.stay[t][s]:
                s = self.prev_best[t]
        if k < base:
            return -1
        sk = st[k - base]
        for t in range(k + 1, last + 1):
            if st[t - base] != sk:
                return t
        return -1

    # ---- change-point fit ----
    def _fit_side(self, pre, py, pyy, lo, hi):
        n = hi - lo
        sy, syy = py[hi] - py[lo], pyy[hi] - pyy[lo]
        dn = float(n)
        level = sy / dn
        rss0 = max(0.0, syy - sy * sy / dn)
        best_j = dn * math.log1p(rss0 / (dn * FIT_FLOOR * FIT_FLOOR)) + math.log(dn)
        best_w, best_a, best_b = -1, 0.0, 0.0
        if n < FIT_MIN_SIN:
            return best_j, level, best_w, best_a, best_b
        pen3 = 3.0 * math.log(dn)
        for w in range(FIT_OMEGAS):
            a, b = pre[w][hi], pre[w][lo]
            ss, sc, cc, s1, c1 = a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3], a[4] - b[4]
            ys, yc = a[5] - b[5], a[6] - b[6]
            d00 = ss * cc - sc * sc
            d01 = s1 * cc - sc * c1
            d02 = s1 * sc - ss * c1
            det = dn * d00 - s1 * d01 + c1 * d02
            if abs(det) < 1e-9 * dn * dn * dn:
                continue
            m = (sy * d00 - s1 * (ys * cc - sc * yc) + c1 * (ys * sc - ss * yc)) / det
            am = (dn * (ys * cc - sc * yc) - sy * d01 + c1 * (s1 * yc - ys * c1)) / det
            bm = (dn * (ss * yc - ys * sc) - s1 * (s1 * yc - ys * c1) + sy * d02) / det
            if am * am + bm * bm > FIT_AMP_CAP * FIT_AMP_CAP:
                continue
            rss = max(0.0, syy - (m * sy + am * ys + bm * yc))
            j = dn * math.log1p(rss / (dn * FIT_FLOOR * FIT_FLOOR)) + pen3
            if j < best_j:
                best_j, level, best_w, best_a, best_b = j, m, w, am, bm
        return best_j, level, best_w, best_a, best_b

    @staticmethod
    def _extend_rmse(side, t, y, lo, hi):
        """Root-mean-square miss of frames [lo, hi) against the model of the other side extended over them."""
        _, level, w, am, bm = side
        pred = np.full(hi - lo, level)
        if w >= 0:
            om = TWO_PI * (FIT_OMEGA_LO + FIT_OMEGA_STEP * w)
            pred = pred + am * np.sin(om * t[lo:hi]) + bm * np.cos(om * t[lo:hi])
        e = y[lo:hi] - pred
        return math.sqrt(float(np.sum(e * e)) / (hi - lo))

    def _change_point(self, k, last_frame, at_end, hole_lo=-1):
        # hole_lo >= 0: frames [hole_lo, k) are a transient dwell of the path at the head of the new note (Amendment 4):
        # the boundary is anchored at hole_lo and the right side starts at k.
        kk = hole_lo if hole_lo >= 0 else k
        # the last frames of a run take no part in a fit and cannot propose a boundary (see notes_hmm.hpp)
        last = last_frame - END_SKIP if at_end else last_frame
        # Amendment 4: the next switch of the path bounds the data of this fit, so a window never holds two boundaries
        kn = self._next_switch(last_frame, k)
        if kn > 0:
            last = min(last, kn - 1)
        if k > last:
            return None
        min_l = FIT_MIN_EDGE
        min_r = FIT_MIN_EDGE
        jlo = max(kk - HMM_SEARCH, self.note_start + self.min, 1)
        jhi = min(k + HMM_AHEAD, last - (min_r + 3))
        i0 = max(self.note_start + 3, kk - HMM_SEARCH - FIT_BACK, last - (FIT_MAX - 1))
        if self.note_start == 0 and last >= 2 * FIT_LEAD - 1 and last < 256:    # glitch frames at the start of the run
            v = sorted(self.ring[FIT_LEAD + i][1] for i in range(FIT_LEAD))
            ref = 0.5 * (v[FIT_LEAD // 2 - 1] + v[FIT_LEAD // 2])
            for i in range(FIT_LEAD):
                if abs(self.ring[i][1] - ref) > FIT_GLITCH:
                    i0 = max(i0, i + 1)
        # a transient at the head of the new note: the dwell starts at the step, so keep the HMM's frame (see notes_hmm.hpp)
        if hole_lo >= 0:
            return self._fallback(kk, k, i0, last)
        # no long side to fit from: keep the HMM's own switch frame
        if kk - i0 < FIT_MIN_SIDE and last - k + 1 < FIT_MIN_SIDE:
            return self._fallback(kk, k, i0, last)
        m = last - i0 + 1
        t0, y0 = self.ring[kk][0].t, self.ring[kk][1]
        t = np.array([self.ring[i0 + i][0].t - t0 for i in range(m)])
        y = np.array([self.ring[i0 + i][1] - y0 for i in range(m)])
        py = np.concatenate([[0.0], np.cumsum(y)])
        pyy = np.concatenate([[0.0], np.cumsum(y * y)])
        pre = np.zeros((FIT_OMEGAS, m + 1, 7))
        for w in range(FIT_OMEGAS):
            ph = TWO_PI * (FIT_OMEGA_LO + FIT_OMEGA_STEP * w) * t
            s, c = np.sin(ph), np.cos(ph)
            cols = (s * s, s * c, c * c, s, c, y * s, y * c)
            for q in range(7):
                pre[w, 1:, q] = np.cumsum(cols[q])
        cand = []      # (J, idx, t, step)
        both_short = ext_rejected = False
        for j in range(jlo, jhi + 1):
            mj = j - i0
            if mj < 1:
                continue
            tau = 0.5 * (t[mj - 1] + t[mj])
            il = mj
            while il > 0 and t[il - 1] >= tau - self.hw:
                il -= 1
            ir = mj
            while ir < m and t[ir] <= tau + self.hw:
                ir += 1
            ll, rh = max(0, il - FIT_BACK), min(m, ir + FIT_BACK)
            if il - ll < min_l or rh - ir < min_r:
                continue
            sa = self._fit_side(pre, py, pyy, ll, il)
            sb = self._fit_side(pre, py, pyy, ir, rh)
            short_l, short_r = il - ll < FIT_MIN_SIDE, rh - ir < FIT_MIN_SIDE
            if short_l and short_r:
                both_short = True
                continue
            if short_l or short_r:      # a short edge side: the long side's model must not explain it
                miss = self._extend_rmse(sb, t, y, ll, il) if short_l else self._extend_rmse(sa, t, y, ir, rh)
                if miss < FIT_MIN_STEP:
                    ext_rejected = True
                    continue
            cand.append((sa[0] + sb[0], j, t0 + tau, sb[1] - sa[1]))
        if not cand:
            return self._fallback(kk, k, i0, last) if both_short and not ext_rejected else None
        best = min(c[0] for c in cand)
        amin = 0
        for i in range(1, len(cand)):
            if cand[i][0] < cand[amin][0]:
                amin = i
        c0 = c1 = amin
        while c0 > 0 and cand[c0 - 1][0] <= best + FIT_TIE:
            c0 -= 1
        while c1 + 1 < len(cand) and cand[c1 + 1][0] <= best + FIT_TIE:
            c1 += 1
        t_mid = 0.5 * (cand[c0][2] + cand[c1][2])
        pick = c0
        for i in range(c0, c1 + 1):
            if abs(cand[i][2] - t_mid) < abs(cand[pick][2] - t_mid):
                pick = i
        return dict(idx=cand[pick][1], t=t_mid, step=cand[pick][3])

    def _median_c(self, lo, hi):
        v = sorted(self.ring[i][1] for i in range(lo, min(hi, lo + FIT_MAX)))
        n = len(v)
        return v[n // 2] if n & 1 else 0.5 * (v[n // 2 - 1] + v[n // 2])

    def _fallback(self, kk, k, i0, last):
        """No long side (two short notes side by side): keep the HMM's own switch frame kk."""
        lo_l, hi_l = max(i0, self.note_start + 3), kk
        lo_r, hi_r = k, last + 1
        if hi_l - lo_l < FIT_MIN_EDGE or hi_r - lo_r < FIT_MIN_EDGE:
            return None
        return dict(idx=kk, t=0.5 * (self.ring[kk - 1][0].t + self.ring[kk][0].t),
                    step=self._median_c(lo_r, hi_r) - self._median_c(lo_l, hi_l))

    def _commit(self, k, label, last, at_end=False):
        if k < self.next_add:
            return []
        out = []
        fr, _, rms = self.ring[k]
        split = False
        if self.hole_lo >= 0 and k >= self.skip_until and label == self.label_prev:
            self.hole_lo = -1                      # the path came back to the same note
        if self.label_prev >= 0 and label != self.label_prev and k < self.skip_until:
            pass                                   # inside a transient dwell: no proposal
        elif self.label_prev >= 0 and label != self.label_prev:
            # a dwell of the path in another state shorter than FIT_MIN_EDGE frames before the next switch is not a note:
            # an octave-error glitch at the head of the next note (or of a return to the same note)
            kn = self._next_switch(last, k)
            if kn > 0 and kn - k < FIT_MIN_EDGE:
                self.skip_until = kn
                if self.hole_lo < 0:
                    self.hole_lo = k
            else:
                sign = 1 if label > self.label_prev else -1
                fit = self._change_point(k, last, at_end, self.hole_lo)
                self.hole_lo = -1
                if fit is not None and sign * fit["step"] >= FIT_MIN_STEP:
                    split = True
                    self._place(fit["idx"], fit["t"], label, k, out)
        if not split:
            if rms and self.label_prev >= 0:
                s = self.seg.boundary(0, fr.t)
                if s is not None:
                    out.append(s)
                self.note_start = k
            self.seg.add(fr)
            self.next_add = k + 1
        if not (k < self.skip_until or (self.hole_lo >= 0 and label != self.label_prev)):
            self.label_prev = label
        return out

    def _place(self, tau, t_b, label, k, out):
        for j in range(self.next_add, tau):
            self.seg.add(self.ring[j][0])
        off = self.ring[k][0].c - self.ring[k][1]
        new_c = 100.0 * (HMM_MIDI_LO + label - 69) + off
        s = self.seg.boundary(max(0, self.next_add - tau), t_b, new_c)
        if s is not None:
            out.append(s)
        self.note_start = tau
        for j in range(max(tau, self.next_add), k + 1):
            self.seg.add(self.ring[j][0])
        self.next_add = max(tau, k + 1)

    def _finish(self):
        out = []
        last = self.n - 1
        if self.committed <= last:
            labels = [0] * (last - self.committed + 1)
            s = self._best_state()
            for t in range(last, self.committed - 1, -1):
                labels[t - self.committed] = s
                if not self.stay[t][s]:
                    s = self.prev_best[t]
            for k in range(self.committed, last + 1):
                out += self._commit(k, labels[k - self.committed], last, True)
        s = self.seg.end()
        if s is not None:
            out.append(s)
        self.open = False
        self.pending_rms = False
        return out


def run_stream(x, cfg=None, tuning=0, a4=440.0, tonic=60):
    """Whole-clip analysis the way the engine does it. Returns (YinResult, onset[bool], notes[list[Note]]).
    Pass audio that already ends in >=0.12 s of silence if the last note must close (the C++ has no flush call)."""
    cfg = cfg or yin_ref.YinConfig()
    r = yin_ref.analyse(x, cfg)
    n = len(r.t)
    db, changed = r.extra["db"], r.extra["note_changed"]
    gate = r.extra["gate"]
    onset = np.zeros(n, dtype=bool)
    notes: list[Note] = []
    half_window = 0.5 * cfg.window_size / cfg.sample_rate if hasattr(cfg, "window_size") else 0.5 * 1024 / 48000.0
    tracker = NoteTracker(NOTE_END_GAP, NOTE_MIN_FRAMES, half_window)

    db_prev = [-200.0] * 3
    since_onset = 1000
    last_c = pre_jump = 0.0
    prev_voiced = have_last = False
    pending = 0
    gap = 1000
    raw_hist: list[float] = []      # previous <=4 frames of the voiced run
    disp_hist: list[float] = []
    for i in range(n):
        voiced = bool(r.voiced[i])
        c_hz, guarded = r.hz_centre[i], r.hz[i]
        on = False
        if i >= 3 and gate[i] and since_onset > ONSET_REFRACTORY and db[i] - min(db_prev) > ONSET_RISE_DB:
            on = True
        rms_on = on                                   # the tracker splits on this one only
        note_voiced = voiced and c_hz > 0 and guarded > 0
        if note_voiced:
            disp = 1200 * np.log2(c_hz / 440.0)
            raw = 1200 * np.log2(guarded / 440.0)
            if not prev_voiced:
                if have_last and gap <= RESUME_GAP_FRAMES and abs(disp - last_c) > PITCH_MOVE_C:
                    on = True
                pending = 0
            elif pending == 0:
                start = False
                if changed[i]:
                    pre_jump, start = last_c, True
                elif (len(raw_hist) >= STEP_SPAN_FRAMES and abs(raw - raw_hist[-1]) < STEP_SETTLED_C
                      and abs(raw - raw_hist[0]) > STEP_SPAN_C):
                    pre_jump, start = disp_hist[0], True
                pending = PITCH_MOVE_FRAMES - 1 if (start and abs(raw - pre_jump) > PITCH_MOVE_C) else 0
            else:
                if abs(raw - pre_jump) > PITCH_MOVE_C:
                    pending -= 1
                    if pending == 0:
                        on = True
                else:
                    pending = 0
            raw_hist = (raw_hist + [raw])[-STEP_SPAN_FRAMES:]
            disp_hist = (disp_hist + [disp])[-STEP_SPAN_FRAMES:]
            last_c, have_last, gap, prev_voiced = disp, True, 0, True
        else:
            prev_voiced, pending = False, 0
            raw_hist, disp_hist = [], []
            if gap < 100000:
                gap += 1
        if on and since_onset <= ONSET_REFRACTORY:
            on = False
        since_onset = 0 if on else since_onset + 1
        db_prev = [db_prev[1], db_prev[2], db[i]]
        onset[i] = on

        nf = NoteFrame(t=float(r.t[i]))
        cents_a4 = 0.0
        if note_voiced:
            nf.c = 1200 * np.log2(guarded / 440.0)
            cents_a4 = 1200 * np.log2(guarded / a4)
            nf.vr, nf.vw = float(r.vib_rate[i]), float(r.vib_width[i])
            nf.ctr = 1200 * np.log2(c_hz / 440.0)
        nf.conf = float(r.confidence[i])
        for s in tracker.update(note_voiced, rms_on, nf, cents_a4):
            hz = 440.0 * 2 ** (s["mean_c"] / 1200)
            _, midi, cents = nearest_target(hz, tuning, a4, tonic)
            notes.append(Note(s["t_start"], s["t_end"], midi, cents, s["std_c"], s["vib_rate"], s["vib_width"],
                              s["mean_conf"], s["frames"]))      # the harness reads continuously, so the 64-entry ring never fills
    return r, onset, notes
