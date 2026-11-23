#!/usr/bin/env python3
"""ADR 0006 mixture generator: violin-like phrases (NSynth acoustic strings) and speech, with known truth, 48 kHz mono.

  gen_mix.py --pool dev --seeds 9401 9402 [--clips 28] [--out testdata/voice/mix/dev] [--public testdata/public]
             [--pools testdata/voice/pools.json] [--noise-dir DIR_OF_MUSAN_NOISE_WAVS_WITH_LICENCE_ENTRIES]

Layouts (cycled, one speech group per clip cycling over ls:adult / so:adult / so:child):
  a speech only | b speech between phrases | c speech overlapping note ends and starts | d violin and speech together at
  violin-over-speech levels +20,+10,+6,0,-6 dB | v violin only | n noise only
Conditions (cycled): clean, noise, reverb, aac, opus, noise+reverb, noise+aac; 0.5 s of noise lead-in, or none on 1 clip in 5.
Seeds: dev 9401-9499, sealed 44001-44004 only (a sealed set is generated from the sealed pool; running it is gated in eval_gates.py).
Deterministic: the same seed and the same corpora give the same files. Pools only: a clip draws speakers and instruments from the pool named.
"""
import argparse
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal

from common import (DEFAULT_PUBLIC, ENGINE_SR, ROOT, align_lag, load_audio, read_json, resample, rms_db, scale_to_db, write_json, write_wav)

LAYOUTS = ["a", "b", "c", "d", "v", "n"]
CONDS = [("clean", {}), ("noise", {"noise": True}), ("reverb", {"reverb": True}), ("aac", {"codec": "aac"}), ("opus", {"codec": "opus"}),
         ("noise+reverb", {"noise": True, "reverb": True}), ("noise+aac", {"noise": True, "codec": "aac"})]
LEVELS_DB = [20, 10, 6, 0, -6]
SPEECH_GROUPS = ["ls", "so_adult", "so_child"]
VIOLIN_DB, SPEECH_DB = -26.0, -26.0
MIN_PITCH, MAX_PITCH = 55, 100        # G3 .. E7


class Corpora:
    def __init__(self, public, pools, pool):
        self.public, self.pool = public, pool
        self.man = {c: read_json(os.path.join(public, c, "manifest.json")) for c in ("librispeech", "nsynth", "speechocean762", "musan")
                    if os.path.exists(os.path.join(public, c, "manifest.json"))}
        keep = lambda st: set(pools["groups"].get(st, {}).get(pool, []))
        self.speech = {"ls": [], "so_adult": [], "so_child": []}
        for it in self.man.get("librispeech", {"items": []})["items"]:
            if it["speaker"] in keep(it["stratum"]):
                self.speech["ls"].append(("librispeech", it))
        for it in self.man.get("speechocean762", {"items": []})["items"]:
            if it["speaker"] in keep(it["stratum"]):
                self.speech["so_child" if it["group"] == "child" else "so_adult"].append(("speechocean762", it))
        self.violin = [("nsynth", it) for it in self.man.get("nsynth", {"items": []})["items"]
                       if it["stratum"] == "ns:string_acoustic" and it["speaker"] in keep("ns:string_acoustic") and MIN_PITCH <= it["pitch"] <= MAX_PITCH]
        self.noise = []
        if os.path.exists(os.path.join(public, "musan", "manifest.json")):
            m = read_json(os.path.join(public, "musan", "manifest.json"))
            self.noise = [("musan", it) for it in m["items"] if it.get("licence_entry_found")]
        for k in self.speech:
            self.speech[k].sort(key=lambda t: t[1]["path"])
        self.violin.sort(key=lambda t: t[1]["path"])

    def path(self, corpus, it):
        return os.path.join(self.man[corpus]["data_root"], it["path"])


def pink(rng, n):
    w = rng.standard_normal(n + 1024)
    b, a = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400]
    return signal.lfilter(b, a, w)[1024:].astype(np.float32)


def violin_note(rng, co, dur):
    corpus, it = co.violin[rng.integers(len(co.violin))]
    x, sr = load_audio(co.path(corpus, it))
    x = resample(x, sr, ENGINE_SR)
    n = int(dur * ENGINE_SR)
    seg = x[:n].copy()
    if len(seg) < n:
        seg = np.pad(seg, (0, n - len(seg)))
    f = int(0.02 * ENGINE_SR)
    seg[-f:] *= np.linspace(1, 0, f, dtype=np.float32)
    body = seg[: int(0.5 * len(seg))]
    seg = scale_to_db(seg, VIOLIN_DB + rng.uniform(-3, 3)) if rms_db(body) > -80 else seg
    return seg, it


def phrase(rng, co, start, n_notes=None):
    """Returns (audio, notes) with notes placed from `start` seconds (relative to the phrase), onset/offset in seconds."""
    n_notes = n_notes or int(rng.integers(3, 9))
    t, parts, notes = 0.0, [], []
    for k in range(n_notes):
        dur = float(rng.choice([0.075, 0.1, rng.uniform(0.12, 1.5)], p=[0.08, 0.1, 0.82]))
        seg, it = violin_note(rng, co, dur)
        legato = k > 0 and rng.random() < 0.3
        gap = 0.0 if legato else float(rng.uniform(0.05, 0.4))
        t0 = t + (-0.01 if legato else gap) if k else 0.0
        notes.append(dict(onset=start + max(0.0, t0), offset=start + max(0.0, t0) + dur, midi=int(it["pitch"]), velocity=int(it["velocity"]),
                          quality=list(it.get("qualities", [])), instrument=it["speaker"], dur=dur))
        parts.append((max(0.0, t0), seg))
        t = max(0.0, t0) + dur
    total = int((t + 0.05) * ENGINE_SR)
    y = np.zeros(total, np.float32)
    for t0, seg in parts:
        i = int(t0 * ENGINE_SR)
        y[i: i + len(seg)] += seg[: max(0, total - i)]
    return y, notes


def utterance(rng, co, group):
    corpus, it = co.speech[group][rng.integers(len(co.speech[group]))]
    x, sr = load_audio(co.path(corpus, it))
    x = resample(x, sr, ENGINE_SR)
    env = np.convolve(np.abs(x), np.ones(int(0.02 * ENGINE_SR)) / int(0.02 * ENGINE_SR), "same")
    keep = np.where(env > env.max() * 0.01)[0]       # trim leading and trailing silence (-40 dB)
    x = x[keep[0]: keep[-1] + 1] if len(keep) else x
    return scale_to_db(x, SPEECH_DB), it["speaker"]


def place(buf, seg, t):
    i = int(round(t * ENGINE_SR))
    if i + len(seg) > len(buf):
        buf = np.pad(buf, (0, i + len(seg) - len(buf)))
    buf[i: i + len(seg)] += seg
    return buf


def build_layout(rng, co, layout, group, level_db):
    buf = np.zeros(int(0.1 * ENGINE_SR), np.float32)
    notes, speech = [], []
    t = 0.0

    def add_speech(buf, t, level=0.0):
        u, spk = utterance(rng, co, group)
        u = (u * 10.0 ** (level / 20.0)).astype(np.float32)
        speech.append(dict(start=t, end=t + len(u) / ENGINE_SR, speaker=spk, group=group))
        return place(buf, u, t), t + len(u) / ENGINE_SR

    def add_phrase(buf, t):
        y, nn = phrase(rng, co, t)
        notes.extend(nn)
        return place(buf, y, t), t + len(y) / ENGINE_SR

    if layout == "a":
        for _ in range(int(rng.integers(2, 5))):
            buf, t = add_speech(buf, t)
            t += float(rng.uniform(0.5, 1.5))
    elif layout == "b":
        for _ in range(int(rng.integers(2, 4))):
            buf, t = add_phrase(buf, t)
            t += float(rng.uniform(0.3, 1.0))
            buf, t = add_speech(buf, t)
            t += float(rng.uniform(0.3, 1.0))
    elif layout == "c":
        buf, t_end = add_phrase(buf, t)
        buf, t_s_end = add_speech(buf, max(0.0, t_end - float(rng.uniform(0.05, 0.3))))   # speech starts inside the last note's tail
        buf, _ = add_phrase(buf, max(0.0, t_s_end - float(rng.uniform(0.05, 0.3))))        # a phrase starts inside the speech
    elif layout == "d":
        y, nn = phrase(rng, co, 0.0, n_notes=int(rng.integers(4, 9)))
        notes.extend(nn)
        buf = place(buf, y, 0.0)
        u_total = len(y) / ENGINE_SR
        tt = 0.0
        while tt < u_total:   # speech under the whole phrase at violin-over-speech = level_db
            buf, tt = add_speech(buf, tt, level=-(level_db) + 0.0)
            tt += float(rng.uniform(0.1, 0.4))
    elif layout == "v":
        for _ in range(int(rng.integers(2, 4))):
            buf, t = add_phrase(buf, t)
            t += float(rng.uniform(0.4, 1.0))
    elif layout == "n":
        pass
    return buf, notes, speech


def eq(rng, x):
    tilt = rng.uniform(-3, 3)
    lp = signal.sosfilt(signal.butter(1, 800, "lowpass", fs=ENGINE_SR, output="sos"), x)
    g = 10 ** (tilt / 20) - 1
    return (x + g * lp).astype(np.float32)


def reverb(rng, x):
    t60 = rng.uniform(0.2, 0.8)
    n = int(t60 * ENGINE_SR)
    ir = rng.standard_normal(n) * np.exp(-6.9 * np.arange(n) / n)
    ir[0] = 1.0
    ir /= np.sqrt(np.sum(ir ** 2))
    return signal.fftconvolve(x, 0.35 * ir + 0.65 * np.eye(1, n)[0])[: len(x)].astype(np.float32), t60


def codec(x, name):
    with tempfile.TemporaryDirectory() as td:
        a, b, c = (os.path.join(td, n) for n in ("in.wav", "enc." + ("m4a" if name == "aac" else "opus"), "out.wav"))
        write_wav(a, x, ENGINE_SR)
        enc = ["-c:a", "aac", "-b:a", "64k"] if name == "aac" else ["-c:a", "libopus", "-b:a", "24k"]
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", a] + enc + [b], check=True)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", b, "-ar", str(ENGINE_SR), "-ac", "1", c], check=True)
        y, _ = load_audio(c)
    lag = align_lag(x, y) if len(y) > 8000 else 0
    y = y[lag:]
    y = np.pad(y, (0, max(0, len(x) - len(y))))[: len(x)]
    return y.astype(np.float32), lag


def make_clip(rng, co, idx):
    layout = LAYOUTS[idx % len(LAYOUTS)]
    cname, cond = CONDS[(idx // len(LAYOUTS)) % len(CONDS)]
    group = SPEECH_GROUPS[(idx // 3) % 3]
    if layout in ("a", "b", "c", "d") and not co.speech[group]:
        group = next(g for g in SPEECH_GROUPS if co.speech[g])
    level = LEVELS_DB[(idx // 5) % len(LEVELS_DB)]
    buf, notes, speech = build_layout(rng, co, layout, group, level)
    meta = dict(layout=layout, cond=cname, speech_group=group if speech else None, violin_over_speech_db=level if layout == "d" else None)
    buf = eq(rng, buf)
    if cond.get("reverb"):
        buf, meta["t60"] = reverb(rng, buf)
    lead = 0.0 if idx % 5 == 4 else 0.5
    meta["lead_in"] = lead > 0
    noise_db = None
    if cond.get("noise") or lead or layout == "n":
        snr = float(rng.uniform(10, 30)) if cond.get("noise") else 40.0
        ref = rms_db(buf[buf != 0]) if np.any(buf != 0) else VIOLIN_DB
        nz = None
        if co.noise and rng.random() < 0.5:
            corpus, it = co.noise[rng.integers(len(co.noise))]
            nz, sr = load_audio(co.path(corpus, it))
            nz = resample(nz, sr, ENGINE_SR)
            meta["noise_file"] = it["id"]
        n_len = len(buf) + int(lead * ENGINE_SR) + int(0.4 * ENGINE_SR)
        if nz is None or len(nz) < 1000:
            nz = pink(rng, n_len)
        nz = np.tile(nz, int(np.ceil(n_len / len(nz))))[:n_len]
        nz = scale_to_db(nz, ref - snr)
        noise_db = ref - snr
        out = np.zeros(n_len, np.float32)
        out[int(lead * ENGINE_SR): int(lead * ENGINE_SR) + len(buf)] = buf
        buf = out + nz
        meta["snr_db"] = snr
    else:
        buf = np.concatenate([np.zeros(int(lead * ENGINE_SR), np.float32), buf, np.zeros(int(0.4 * ENGINE_SR), np.float32)])
    for n in notes:
        n["onset"] += lead
        n["offset"] += lead
    for s in speech:
        s["start"] += lead
        s["end"] += lead
    if rng.random() < 0.1:
        buf = np.clip(buf * 10 ** (rng.uniform(0, 3) / 20) * 8, -1, 1) / 8     # 0 to 3 dB over a ceiling (rare)
        meta["clipped"] = True
    peak = np.max(np.abs(buf)) + 1e-9
    if peak > 0.95:
        buf = buf * (0.95 / peak)
    if cond.get("codec"):
        buf, lag = codec(buf, cond["codec"])
        meta["codec_lag_samples"] = lag
    return buf.astype(np.float32), dict(sr=ENGINE_SR, notes=notes, speech=speech, **meta)


def check_seed(pool, seed):
    ok = (9400 <= seed < 9500) if pool == "dev" else seed in range(44001, 44005)
    if not ok:
        raise SystemExit(f"seed {seed} is not allowed for pool '{pool}' (dev 9400-9499, sealed 44001-44004)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pool", choices=["dev", "sealed"], required=True)
    ap.add_argument("--seeds", type=int, nargs="+", required=True)
    ap.add_argument("--clips", type=int, default=28)
    ap.add_argument("--public", default=DEFAULT_PUBLIC)
    ap.add_argument("--pools", default=os.path.join(ROOT, "testdata", "voice", "pools.json"))
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    for s in a.seeds:
        check_seed(a.pool, s)
    out = a.out or os.path.join(ROOT, "testdata", "voice", "mix", a.pool)
    co = Corpora(a.public, read_json(a.pools), a.pool)
    if not co.violin or not any(co.speech.values()):
        raise SystemExit("pool has no violin notes or no speech; check intake and pools")
    os.makedirs(out, exist_ok=True)
    index = []
    for seed in a.seeds:
        rng = np.random.default_rng(seed)
        for i in range(a.clips):
            x, truth = make_clip(rng, co, i)
            name = f"s{seed}_c{i:03d}_{truth['layout']}"
            write_wav(os.path.join(out, name + ".wav"), x, ENGINE_SR)
            truth["file"] = name + ".wav"
            truth["seed"] = seed
            write_json(os.path.join(out, name + ".json"), truth)
            index.append(truth["file"])
    write_json(os.path.join(out, f"index_{'_'.join(map(str, a.seeds))}.json"), index)
    print(f"{len(index)} clips in {out}")


if __name__ == "__main__":
    main()
