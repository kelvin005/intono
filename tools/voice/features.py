#!/usr/bin/env python3
"""ADR 0006 candidate features F1..F7, offline, with the engine's framing (window 1024, hop 256, hop centre times).

  features.py --mix-dir DIR --cli CLI --out feats.npz [--cli-extra ...]

Per engine hop (the frames the CLI prints) this computes F1..F7 from the engine's own outputs (display pitch = the ADR 0001 vibrato
centre, confidence, voiced flag) and from the audio. Frames and notes are those of the FROZEN engine (the base of every gate).
Feature scaling to [0, 1] uses FIXED constants written below, chosen from the definitions before any data was seen. They are not fitted.

Known offline simplification, to be removed by the parity test when the C++ version exists: the spectrum is taken from a
2048-sample Hann window centred on the engine window's centre of the engine-filtered audio (causal 2nd-order high-pass 150 Hz
and low-pass 4 kHz), as the C++ feature would have it.
"""
import argparse
import os

import numpy as np
from scipy import signal

from common import BAND_HZ, FROZEN_CLI, HOP, WIN, engine_filter, hop_centre_times, load_audio, read_json, run_cli

FEATURES = ["F1_conf", "F2_comb", "F3_regularity", "F4_centroid", "F5_stability", "F6_voiced_frac", "F7_rms_mod"]
# fixed scaling ranges (lo, hi), a priori; value -> clip((v - lo) / (hi - lo), 0, 1)
SCALE = {"F1_conf": (0.0, 1.0), "F2_comb": (0.0, 1.0), "F3_regularity": (0.0, 4.0), "F4_centroid": (0.0, 12.0),
         "F5_stability": (0.0, 1.0), "F6_voiced_frac": (0.0, 1.0), "F7_rms_mod": (0.0, 6.0)}
N_STAB = 20            # F5 window (hops), a free number of ADR 0006 (the "stability window N")
STAB_CENTS = 8.0       # fixed in advance: per-hop change under 8 cents of the vibrato centre counts as stable
FFT_N = 2048
N_HARM = 8


def scale(name, v):
    lo, hi = SCALE[name]
    return np.clip((v - lo) / (hi - lo), 0.0, 1.0)


def spectrum_features(x, sr, centres_samples, f0):
    """F2, F3, F4 for each hop. f0: display pitch in Hz (0 = none). Returns three arrays (NaN where undefined)."""
    n = len(centres_samples)
    F2, F3, F4 = (np.full(n, np.nan) for _ in range(3))
    win = signal.windows.hann(FFT_N, sym=False).astype(np.float32)
    pad = np.pad(x, (FFT_N, FFT_N))
    freqs = np.fft.rfftfreq(FFT_N, 1.0 / sr)
    band = freqs <= BAND_HZ
    for i in range(n):
        if f0[i] <= 0:
            continue
        s = int(centres_samples[i]) - FFT_N // 2 + FFT_N
        P = np.abs(np.fft.rfft(pad[s: s + FFT_N] * win)) ** 2
        best = None
        for base in (f0[i], f0[i] / 2.0):               # the better of f0 and f0/2 (octave-error guard, ADR 0006 item 4)
            ks = np.arange(1, N_HARM + 1)
            fk = ks * base
            fk = fk[fk < BAND_HZ]
            if len(fk) < 3:
                continue
            tol = 0.25 * base
            in_comb = np.zeros(len(freqs), bool)
            amps = []
            for f in fk:
                m = np.abs(freqs - f) <= tol
                in_comb |= m
                amps.append(P[m].sum() + 1e-12)
            top = min(fk[-1] + 0.5 * base, BAND_HZ)
            den = P[(freqs >= 0.5 * base) & (freqs <= top)].sum() + 1e-12
            h = float(np.clip(sum(amps) / den, 0.0, 1.0))
            la = np.log(np.array(amps))
            reg = float(np.std(np.diff(la, 2))) if len(la) >= 4 else np.nan
            cen = float((freqs[band] * P[band]).sum() / (P[band].sum() + 1e-12) / f0[i])
            if best is None or h > best[0]:
                best = (h, reg, cen)
        if best:
            F2[i], F3[i], F4[i] = best
    return F2, F3, F4


def stability(ctr_cents, voiced, n=N_STAB):
    """F5: max(stable fraction, monotone fraction) of the per-hop change of the display centre over the last n hops (voiced runs only)."""
    N = len(ctr_cents)
    out = np.full(N, np.nan)
    d = np.full(N, np.nan)
    d[1:] = np.where(voiced[1:] & voiced[:-1], np.diff(ctr_cents), np.nan)
    for i in range(N):
        w = d[max(0, i - n + 1): i + 1]
        w = w[~np.isnan(w)]
        if len(w) < 3:
            continue
        stable = np.mean(np.abs(w) < STAB_CENTS)
        sgn = np.sign(w[np.abs(w) >= 1.0])
        mono = 0.0 if len(sgn) < 3 else abs(sgn.sum()) / len(w)
        out[i] = max(stable, min(mono, 1.0))
    return out


def voiced_fraction(voiced, n=20):
    c = np.cumsum(np.concatenate([[0], voiced.astype(float)]))
    idx = np.arange(1, len(voiced) + 1)
    lo = np.maximum(0, idx - n)
    return (c[idx] - c[lo]) / (idx - lo)


def rms_modulation(db, hop_sr, voiced):
    """F7: std (dB) of the 3-8 Hz band of the hop-rate level, over the last 1 s (causal)."""
    sos = signal.butter(2, [3.0, 8.0], "bandpass", fs=hop_sr, output="sos")
    b = signal.sosfilt(sos, np.where(np.isfinite(db), db, -100.0))
    n = int(hop_sr)
    out = np.zeros(len(b))
    c2 = np.cumsum(np.concatenate([[0], b ** 2]))
    idx = np.arange(1, len(b) + 1)
    lo = np.maximum(0, idx - n)
    out = np.sqrt((c2[idx] - c2[lo]) / (idx - lo))
    return out


def clip_features(wav, frames):
    x, sr = load_audio(wav)
    xf = engine_filter(x, sr)
    n_hops = len(frames)
    centres = (np.arange(n_hops) * HOP + WIN / 2.0)
    voiced = frames[:, 7] > 0.5
    hz = frames[:, 1]
    ctr = np.where(hz > 0, 1200.0 * np.log2(np.maximum(hz, 1e-3) / 440.0), np.nan)
    F2, F3, F4 = spectrum_features(xf, sr, centres, np.where(voiced, hz, 0.0))
    db = np.array([20 * np.log10(np.sqrt(np.mean(xf[int(c - WIN / 2): int(c + WIN / 2)] ** 2)) + 1e-9) for c in centres])
    raw = dict(F1_conf=frames[:, 2], F2_comb=F2, F3_regularity=F3, F4_centroid=F4,
               F5_stability=stability(np.nan_to_num(ctr), voiced), F6_voiced_frac=voiced_fraction(voiced),
               F7_rms_mod=rms_modulation(db, sr / HOP, voiced))
    return {k: scale(k, v) for k, v in raw.items()}, voiced, frames[:, 0], db


def label_hops(t, truth):
    """0 speech-only, 1 violin-only, 2 neither (noise), -1 excluded (overlap, or within 150 ms after a note's end)."""
    lab = np.full(len(t), 2, int)
    grp = np.array([""] * len(t), dtype=object)
    v = np.zeros(len(t), bool)
    s = np.zeros(len(t), bool)
    near = np.zeros(len(t), bool)
    for n in truth["notes"]:
        v |= (t >= n["onset"]) & (t <= n["offset"])
        near |= (t > n["offset"]) & (t <= n["offset"] + 0.15)
        grp[(t >= n["onset"]) & (t <= n["offset"] + 0.15)] = n["instrument"]
    for sp in truth["speech"]:
        m = (t >= sp["start"]) & (t <= sp["end"])
        s |= m
        grp[m & ~v] = sp["speaker"]
    lab[s & ~v] = 0
    lab[v & ~s] = 1
    lab[(s & v) | (near & ~s & ~v)] = -1
    return lab, grp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mix-dir", required=True)
    ap.add_argument("--cli", default=FROZEN_CLI)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    cols = {k: [] for k in ["clip", "hop", "t", "voiced", "label", "group", "speech_group", "layout", "cond"] + FEATURES}
    names = sorted(f for f in os.listdir(a.mix_dir) if f.endswith(".wav"))
    for ci, nm in enumerate(names):
        truth = read_json(os.path.join(a.mix_dir, nm[:-4] + ".json"))
        frames = run_cli(a.cli, os.path.join(a.mix_dir, nm))
        feats, voiced, t, db = clip_features(os.path.join(a.mix_dir, nm), frames)
        lab, grp = label_hops(t, truth)
        n = len(t)
        cols["clip"] += [nm] * n
        cols["hop"] += list(range(n))
        cols["t"] += list(t)
        cols["voiced"] += list(voiced)
        cols["label"] += list(lab)
        cols["group"] += list(grp)
        cols["speech_group"] += [truth.get("speech_group") or ""] * n
        cols["layout"] += [truth["layout"]] * n
        cols["cond"] += [truth["cond"]] * n
        for k in FEATURES:
            cols[k] += list(feats[k])
    np.savez_compressed(a.out, **{k: np.array(v) for k, v in cols.items()}, feature_names=np.array(FEATURES))
    print(f"{len(names)} clips, {len(cols['t'])} hops -> {a.out}")


if __name__ == "__main__":
    main()
