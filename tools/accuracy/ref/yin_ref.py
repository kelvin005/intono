"""Phase 0 reference YIN for Intono.

Plain-numpy implementation of the DSP pipeline in the architecture doc, used as
the ground-truth behaviour that libintono (C++) must later match:

  preprocess : DC blocker -> 2nd-order Butterworth HP 150 Hz -> LP 4 kHz
               -> adaptive noise gate (floor learned in first 500 ms, opens at +10 dB)
  pitch      : YIN, cumulative mean normalised difference (FFT-accelerated),
               window 1024, hop 256, 180-3200 Hz, threshold 0.12,
               parabolic interpolation, confidence = 1 - d'(tau)
  octave     : reject ~2x / ~0.5x jumps unless confidence > 0.9 for 3 frames
  centre     : median over one vibrato cycle (4-8 Hz, 10-100 c extent), else 150 ms

Offline and vectorised; not real-time safe (that is the C++ core's job).
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
from scipy import signal


@dataclass
class YinConfig:
    sample_rate: float = 48000.0
    window_size: int = 1024
    hop_size: int = 256
    min_hz: float = 180.0
    max_hz: float = 3200.0
    threshold: float = 0.12
    hp_hz: float = 150.0
    lp_hz: float = 4000.0
    gate_learn_s: float = 0.5
    gate_open_db: float = 10.0
    use_gate: bool = True
    octave_conf: float = 0.9
    octave_frames: int = 3
    contour_s: float = 0.25
    centre_default_s: float = 0.15
    centre_method: str = "extrema"   # "extrema" (ADR 0001), "extrema_v0", or "autocorr" (doc as written)
    vib_min_swing_c: float = 8.0
    note_step_c: float = 30.0       # frame-to-frame jump that starts a new note (resets contour + hold-over)
    slide_margin_c: float = 15.0    # established vibrato: raw pitch this far outside the last peak/trough ...
    slide_persist: int = 2          # ... for this many frames in a row = slide
    flat_range_c: float = 12.0      # steady note: contour range up to this is flat ...
    slide_dev_c: float = 25.0       # ... and a departure this far from it is a slide
    flat_min_frames: int = 12
    recent_frames: int = 6
    follow_frames: int = 4
    settle_frames: int = 20


@dataclass
class YinResult:
    t: np.ndarray            # frame centre times (s)
    hz_raw: np.ndarray       # per-frame YIN estimate (0 = unvoiced)
    hz: np.ndarray           # after octave guard (0 = unvoiced)
    hz_centre: np.ndarray    # displayed centre pitch (0 = unvoiced)
    confidence: np.ndarray
    voiced: np.ndarray       # bool
    vib_rate: np.ndarray     # Hz (0 = no vibrato)
    vib_width: np.ndarray    # cents peak-to-peak (0 = no vibrato)
    extra: dict = field(default_factory=dict)


# ---------------------------------------------------------------- preprocess
def preprocess(x: np.ndarray, cfg: YinConfig) -> np.ndarray:
    sr = cfg.sample_rate
    # DC blocker y[n] = x[n] - x[n-1] + R*y[n-1]
    x = signal.lfilter([1.0, -1.0], [1.0, -0.995], x)
    sos_hp = signal.butter(2, cfg.hp_hz, "highpass", fs=sr, output="sos")
    sos_lp = signal.butter(2, cfg.lp_hz, "lowpass", fs=sr, output="sos")
    x = signal.sosfilt(sos_hp, x)
    x = signal.sosfilt(sos_lp, x)
    return x.astype(np.float64)


def frame_signal(x: np.ndarray, win: int, hop: int) -> np.ndarray:
    if len(x) < win:
        x = np.pad(x, (0, win - len(x)))
    n = 1 + (len(x) - win) // hop
    idx = np.arange(win)[None, :] + hop * np.arange(n)[:, None]
    return x[idx]


def noise_gate(frames: np.ndarray, cfg: YinConfig) -> np.ndarray:
    """Streaming gate, identical to libintono: until the learning period (first gate_learn_s) is over the
    floor is the -50 dBFS cap; from the last learning frame on it is the 20th percentile of the learned
    levels, capped at -50 dBFS. (Phase 0 applied the learned floor retroactively to the whole clip.)"""
    rms = np.sqrt(np.mean(frames**2, axis=1) + 1e-20)
    db = 20 * np.log10(rms + 1e-12)
    n_learn = max(1, int(cfg.gate_learn_s * cfg.sample_rate / cfg.hop_size))
    floor = np.full(len(db), -50.0)
    if len(db) >= n_learn:
        learned = min(float(np.percentile(db[:n_learn], 20)), -50.0)
        floor[n_learn - 1:] = learned
    return db > floor + cfg.gate_open_db


# ---------------------------------------------------------------- YIN core
def yin_frames(frames: np.ndarray, cfg: YinConfig):
    sr, win = cfg.sample_rate, cfg.window_size
    tau_min = max(2, int(np.floor(sr / cfg.max_hz)))
    tau_max = int(np.ceil(sr / cfg.min_hz))
    W = win - tau_max - 1                       # integration window (lags up to tau_max+1)
    assert W > tau_max, "window too short for min_hz"

    nfft = 1 << int(np.ceil(np.log2(win + W)))
    # autocorrelation r(tau) = sum_{j<W} x_j x_{j+tau} via cross-correlation
    X = np.fft.rfft(frames, nfft, axis=1)
    Xw = np.fft.rfft(frames[:, :W], nfft, axis=1)
    r = np.fft.irfft(X * np.conj(Xw), nfft, axis=1)[:, : tau_max + 2]

    sq = np.concatenate([np.zeros((frames.shape[0], 1)), np.cumsum(frames**2, axis=1)], axis=1)
    taus = np.arange(tau_max + 2)
    e0 = sq[:, W] - sq[:, 0]                                  # sum x_j^2, j<W
    etau = sq[:, taus + W] - sq[:, taus]                      # sum x_{j+tau}^2
    d = e0[:, None] + etau - 2 * r
    d = np.maximum(d, 0.0)
    d[:, 0] = 0.0

    # cumulative mean normalised difference
    cum = np.cumsum(d[:, 1:], axis=1)
    dn = np.ones_like(d)
    dn[:, 1:] = d[:, 1:] * np.arange(1, d.shape[1])[None, :] / np.maximum(cum, 1e-20)

    n = frames.shape[0]
    lag = np.zeros(n)
    conf = np.zeros(n)
    found = np.zeros(n, dtype=bool)
    search = dn[:, tau_min : tau_max + 1]
    for i in range(n):
        row = search[i]
        below = np.flatnonzero(row < cfg.threshold)
        if below.size:
            k = below[0]
            while k + 1 < row.size and row[k + 1] < row[k]:
                k += 1                                         # walk to local min
            found[i] = True
        else:
            k = int(np.argmin(row))
        t = k + tau_min
        if found[i] and (t <= tau_min or t >= tau_max):
            found[i] = False            # range-edge minimum = boundary artefact
        if e0[i] < 1e-12:
            found[i] = False            # digital silence
        # parabolic interpolation on dn around t
        if 1 <= t < dn.shape[1] - 1:
            a, b, c = dn[i, t - 1], dn[i, t], dn[i, t + 1]
            den = a - 2 * b + c
            off = 0.5 * (a - c) / den if abs(den) > 1e-12 else 0.0
            off = float(np.clip(off, -1, 1))
        else:
            off = 0.0
        lag[i] = t + off
        conf[i] = float(np.clip(1.0 - dn[i, t], 0.0, 1.0))
    hz = np.where(lag > 0, sr / np.maximum(lag, 1e-9), 0.0)
    return hz, conf, found


# ---------------------------------------------------------------- post
def octave_guard(hz, conf, voiced, cfg: YinConfig):
    out = np.zeros_like(hz)
    last = 0.0
    streak = 0
    for i in range(len(hz)):
        if not voiced[i]:
            out[i] = 0.0
            streak = 0
            last = 0.0          # a new note after silence starts unguarded
            continue
        f = hz[i]
        if last > 0:
            ratio = f / last
            is_jump = abs(np.log2(ratio) - 1) < 0.08 or abs(np.log2(ratio) + 1) < 0.08
            if is_jump:
                streak = streak + 1 if conf[i] > cfg.octave_conf else 0
                if streak >= cfg.octave_frames:
                    last = f
                    out[i] = f
                    streak = 0
                else:
                    # hold the established octave: fold the estimate back
                    out[i] = f / (2 ** round(np.log2(ratio)))
                continue
            streak = 0
        last = f
        out[i] = f
    return out


def centre_pitch(hz, voiced, cfg: YinConfig):
    if cfg.centre_method == "extrema":
        return centre_pitch_extrema(hz, voiced, cfg)[:3]
    if cfg.centre_method == "extrema_v0":
        return centre_pitch_extrema_v0(hz, voiced, cfg)
    return centre_pitch_autocorr(hz, voiced, cfg)


def _zigzag(sm: np.ndarray, min_swing: float):
    """Indices of alternating peaks/troughs whose swing to the previous one is >= min_swing.

    Bumps smaller than min_swing (noise) never become extrema.
    """
    ext = []                       # list of (index, is_max); segment edges are not extrema
    hi = lo = 0
    mode, cand = 0, 0              # mode: +1 tracking a peak, -1 tracking a trough, 0 undecided
    for i in range(1, len(sm)):
        v = sm[i]
        if mode == 0:
            if v > sm[hi]:
                hi = i
            if v < sm[lo]:
                lo = i
            if v - sm[lo] >= min_swing:
                mode, cand = 1, i
            elif sm[hi] - v >= min_swing:
                mode, cand = -1, i
        elif mode == 1:
            if v > sm[cand]:
                cand = i
            elif sm[cand] - v >= min_swing:
                ext.append((cand, True))
                mode, cand = -1, i
        else:
            if v < sm[cand]:
                cand = i
            elif v - sm[cand] >= min_swing:
                ext.append((cand, False))
                mode, cand = 1, i
    return ext


def centre_pitch_extrema(hz, voiced, cfg: YinConfig):
    """ADR 0001 centre pitch / vibrato tracker, mirrored line for line from dsp/src/post.hpp.

    Returns (centre_hz, vib_rate, vib_width, note_changed). Rules, in the order the C++ applies them:
      * a >note_step_c jump between consecutive frames starts a new note (contour and hold-over cleared)
      * slide detection: established vibrato whose raw pitch stays outside the last peak/trough by
        slide_margin_c for slide_persist frames, or a flat contour followed by a departure of slide_dev_c
      * follow mode: show the median of the newest follow_frames until the pitch is flat for
        settle_frames, or a vibrato is recognised in the contour
      * vibrato: peak/trough midpoints (min swing, last 4 extrema), hold-over, 150 ms median fallback
    """
    hop_s = cfg.hop_size / cfg.sample_rate
    n_ctx = int(round(cfg.contour_s / hop_s))
    n_def = int(round(cfg.centre_default_s / hop_s))
    cents = np.where(hz > 0, 1200 * np.log2(np.maximum(hz, 1e-9) / 440.0), np.nan)
    out = np.zeros_like(hz)
    vr = np.zeros_like(hz)
    vw = np.zeros_like(hz)
    changed = np.zeros(len(hz), dtype=bool)
    run: list[float] = []
    held = None                     # (centre, rate, width) of the last established vibrato
    held_n = 0
    follow = False
    have_env = False
    env_lo = env_hi = 0.0
    outside = 0
    last_c = 0.0
    for i in range(len(hz)):
        if not voiced[i] or hz[i] <= 0:
            run, held, follow, have_env, outside = [], None, False, False, 0
            continue
        c = float(cents[i])
        if run and abs(c - last_c) > cfg.note_step_c:
            run, held, follow, have_env, outside = [], None, False, False, 0
            changed[i] = True
        last_c = c
        run.append(c)
        seg = run[-n_ctx:]
        seg_len = len(seg)

        if not follow:
            slide = False
            if held is not None and have_env:
                is_out = c > env_hi + cfg.slide_margin_c or c < env_lo - cfg.slide_margin_c
                outside = outside + 1 if is_out else 0
                slide = outside >= cfg.slide_persist
            elif seg_len >= cfg.flat_min_frames:
                m = seg_len - cfg.recent_frames
                lo, hi = min(seg[:m]), max(seg[:m])
                slide = (hi - lo <= cfg.flat_range_c) and abs(c - 0.5 * (lo + hi)) > cfg.slide_dev_c
            if slide:
                follow, held, have_env, outside = True, None, False, 0
                keep = min(seg_len, cfg.follow_frames)
                seg, seg_len, run = seg[-keep:], keep, run[-keep:]

        have = False
        centre = rate = width = 0.0
        if seg_len >= 9:
            sm = np.convolve(seg, np.ones(3) / 3, mode="valid")
            ext = _zigzag(sm, cfg.vib_min_swing_c)
            if len(ext) >= 2:
                last = ext[-4:]
                mids = [0.5 * (sm[a[0]] + sm[b[0]]) for a, b in zip(last[:-1], last[1:])]
                sw = abs(sm[last[-1][0]] - sm[last[-2][0]])
                half = (last[-1][0] - last[-2][0]) * hop_s
                rt = 1.0 / (2 * half)
                if 10 <= sw <= 100 and 3.5 <= rt <= 9.0:
                    have = True
                    centre, rate, width = float(np.mean(mids)), rt, sw
                    env_lo = min(sm[e[0]] for e in last)
                    env_hi = max(sm[e[0]] for e in last)
        if have:
            follow, have_env = False, True
            held, held_n = (centre, rate, width), 0
        elif follow and seg_len >= cfg.settle_frames:
            tail = seg[-cfg.settle_frames:]
            if max(tail) - min(tail) <= cfg.flat_range_c:
                follow = False
                seg, seg_len, run = seg[-cfg.settle_frames:], cfg.settle_frames, run[-cfg.settle_frames:]

        if not have and follow:
            n = min(seg_len, cfg.follow_frames)
            centre, rate, width = float(np.median(seg[-n:])), 0.0, 0.0
        elif not have and held is not None and held_n < n_ctx and len(run) > 1:
            centre, rate, width = held     # latest extremum not confirmed yet: hold the previous centre
            held_n += 1
        elif not have:
            held, have_env = None, False
            n = min(len(run), n_def)
            centre, rate, width = float(np.median(seg[-n:])), 0.0, 0.0
        out[i] = 440.0 * 2 ** (centre / 1200)
        vr[i], vw[i] = rate, width
    return out, vr, vw, changed


def centre_pitch_extrema_v0(hz, voiced, cfg: YinConfig):
    """Phase 0 first version (latest peak + trough, no safeguards). Kept for comparison.

    Vibrato centre = midpoint of the most recent peak and trough in the contour.

    A >=4 Hz vibrato always shows one interior peak and one interior trough
    inside a 250 ms contour, so this works where autocorrelation cannot
    (autocorrelation needs ~2 periods = 500 ms at 4 Hz).
    """
    hop_s = cfg.hop_size / cfg.sample_rate
    n_ctx = int(round(cfg.contour_s / hop_s))
    n_def = int(round(cfg.centre_default_s / hop_s))
    cents = np.where(hz > 0, 1200 * np.log2(np.maximum(hz, 1e-9) / 440.0), np.nan)
    out = np.zeros_like(hz)
    vr = np.zeros_like(hz)
    vw = np.zeros_like(hz)
    run_start = 0
    for i in range(len(hz)):
        if not voiced[i] or hz[i] <= 0:
            run_start = i + 1
            continue
        s = max(run_start, i - n_ctx + 1)
        seg = cents[s : i + 1]
        centre = None
        if seg.size >= 9:
            sm = np.convolve(seg, np.ones(3) / 3, mode="valid")      # ~16 ms smoothing
            d = np.diff(sm)
            sgn = np.sign(d)
            turn = np.flatnonzero(sgn[1:] * sgn[:-1] < 0) + 1        # interior extrema of sm
            if turn.size >= 2:
                a, b = turn[-2], turn[-1]
                is_max_b = sgn[b - 1] > 0
                is_max_a = sgn[a - 1] > 0
                if is_max_a != is_max_b:
                    width = abs(sm[b] - sm[a])
                    half_period = (b - a) * hop_s
                    rate = 1.0 / (2 * half_period)
                    if 10 <= width <= 100 and 3.5 <= rate <= 9.0:
                        centre = 0.5 * (sm[a] + sm[b])
                        vr[i], vw[i] = rate, width
        if centre is None:
            s2 = max(run_start, i - n_def + 1)
            centre = np.median(cents[s2 : i + 1])
        out[i] = 440.0 * 2 ** (centre / 1200)
    return out, vr, vw


def centre_pitch_autocorr(hz, voiced, cfg: YinConfig):
    hop_s = cfg.hop_size / cfg.sample_rate
    n_ctx = int(round(cfg.contour_s / hop_s))
    n_def = int(round(cfg.centre_default_s / hop_s))
    lag_lo = int(np.floor(1 / 8.0 / hop_s))
    lag_hi = int(np.ceil(1 / 4.0 / hop_s))
    out = np.zeros_like(hz)
    vr = np.zeros_like(hz)
    vw = np.zeros_like(hz)
    cents = np.where(hz > 0, 1200 * np.log2(np.maximum(hz, 1e-9) / 440.0), np.nan)
    run_start = 0
    for i in range(len(hz)):
        if not voiced[i] or hz[i] <= 0:
            run_start = i + 1
            continue
        s = max(run_start, i - n_ctx + 1)
        seg = cents[s : i + 1]
        win = n_def
        if seg.size >= lag_hi + 4:
            z = seg - np.mean(seg)
            ac = np.correlate(z, z, "full")[z.size - 1 :]
            if ac[0] > 0:
                ac = ac / ac[0]
                lo, hi = lag_lo, min(lag_hi, ac.size - 1)
                if hi > lo:
                    k = lo + int(np.argmax(ac[lo : hi + 1]))
                    width = np.percentile(seg, 95) - np.percentile(seg, 5)
                    if ac[k] > 0.3 and 10 <= width <= 100:
                        win = k
                        vr[i] = 1.0 / (k * hop_s)
                        vw[i] = width
        s2 = max(run_start, i - win + 1)
        out[i] = 440.0 * 2 ** (np.median(cents[s2 : i + 1]) / 1200)
    return out, vr, vw


def analyse(x: np.ndarray, cfg: YinConfig | None = None) -> YinResult:
    cfg = cfg or YinConfig()
    y = preprocess(np.asarray(x, dtype=np.float64), cfg)
    frames = frame_signal(y, cfg.window_size, cfg.hop_size)
    hz_raw, conf, found = yin_frames(frames, cfg)
    gate = noise_gate(frames, cfg) if cfg.use_gate else np.ones(len(hz_raw), bool)
    voiced = found & gate
    hz = octave_guard(hz_raw, conf, voiced, cfg)
    changed = np.zeros(len(hz), dtype=bool)
    if cfg.centre_method == "extrema":
        hz_c, vr, vw, changed = centre_pitch_extrema(hz, voiced, cfg)
    else:
        hz_c, vr, vw = centre_pitch(hz, voiced, cfg)
    t = (np.arange(len(hz)) * cfg.hop_size + cfg.window_size / 2) / cfg.sample_rate
    db = 20 * np.log10(np.sqrt(np.mean(frames**2, axis=1) + 1e-20) + 1e-12)
    return YinResult(t, np.where(voiced, hz_raw, 0.0), hz, hz_c, conf, voiced, vr, vw,
                     extra=dict(db=db, gate=gate, note_changed=changed))
