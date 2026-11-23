#!/usr/bin/env python3
"""Plumbing self-test for the ADR 0006 tools on GENERATED STAND-IN corpora (no real data is touched).

  selftest.py [--keep DIR]

Builds tiny stand-ins in the layouts that intake.py expects (LibriSpeech tree + SPEAKERS.TXT, NSynth examples.json + audio/,
speechocean762 WAVE/ + spk2age/spk2gender, MUSAN noise + LICENSE), then runs intake -> pools -> gen_mix -> features -> fit -> eval_gates
(baseline, and a same-binary comparison) and checks the outputs: determinism, pool disjointness, labels, finite features, report shape.
It says nothing about real audio. The stand-ins are crude: 'speech' = moving-formant harmonic source with syllabic modulation and breath,
'violin' = steady bright harmonic tone with vibrato.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from common import FROZEN_CLI, read_json, sha256_file  # noqa: E402

SR = 16000


def speech_like(rng, sec, f0_lo, f0_hi):
    n = int(sec * SR)
    t = np.arange(n) / SR
    f0 = np.cumsum(rng.normal(0, 3.0, n) / SR * 200) + rng.uniform(f0_lo, f0_hi)
    f0 = np.clip(f0 + 12 * np.sin(2 * np.pi * rng.uniform(1, 3) * t), f0_lo * 0.8, f0_hi * 1.2)
    ph = 2 * np.pi * np.cumsum(f0) / SR
    x = np.zeros(n)
    F1 = 500 + 250 * np.sin(2 * np.pi * rng.uniform(0.5, 1.5) * t + rng.uniform(0, 6))
    F2 = 1500 + 600 * np.sin(2 * np.pi * rng.uniform(0.5, 1.5) * t + rng.uniform(0, 6))
    for k in range(1, 31):
        fk = k * f0
        env = 1.0 / k * (1 + 4 / (1 + ((fk - F1) / 120) ** 2) + 3 / (1 + ((fk - F2) / 200) ** 2))
        x += env * np.sin(k * ph) * (fk < 7500)
    am = 0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(3, 5) * t + 1)
    am = np.clip(am, 0.05, 1) ** 1.5
    x = x * am + 0.15 * rng.standard_normal(n) * am.mean()
    gate = (np.sin(2 * np.pi * 0.7 * t + rng.uniform(0, 6)) > -0.6).astype(float)      # pauses
    x = x * np.convolve(gate, np.ones(400) / 400, "same")
    return (0.3 * x / (np.max(np.abs(x)) + 1e-9)).astype(np.float32)


def violin_like(rng, midi, sec=4.0, vib=True):
    n = int(sec * SR)
    t = np.arange(n) / SR
    f0 = 440 * 2 ** ((midi - 69) / 12.0)
    f = f0 * 2 ** ((20 * np.sin(2 * np.pi * 5.5 * t) * (t > 0.2) if vib else 0) / 1200.0)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = sum(np.sin(k * ph) / (k ** 0.9) * (k * f0 < 7500) for k in range(1, 40))
    env = np.minimum(1, t / 0.03) * np.where(t < 3, 1.0, np.clip(1 - (t - 3), 0, 1))
    return (0.3 * x * env / (np.max(np.abs(x * env)) + 1e-9)).astype(np.float32)


def build_corpora(root, rng):
    ls = os.path.join(root, "src_ls", "LibriSpeech")
    os.makedirs(ls)
    lines = ["; stand-in"]
    for s in range(8):
        sid = 1000 + s
        lines.append(f"{sid} | {'F' if s % 2 else 'M'} | test-clean | 8.0 | name{s}")
        d = os.path.join(ls, "test-clean", str(sid), "1")
        os.makedirs(d)
        for u in range(3):
            sf.write(os.path.join(d, f"{sid}-1-{u:04d}.flac"), speech_like(rng, rng.uniform(3, 5), 90, 230), SR)
    open(os.path.join(ls, "SPEAKERS.TXT"), "w").write("\n".join(lines) + "\n")
    for split, n_inst in (("nsynth-test", 10), ("nsynth-valid", 6)):
        d = os.path.join(root, "src_ns", split)
        os.makedirs(os.path.join(d, "audio"))
        ex = {}
        for k in range(n_inst):
            for pitch in (57, 62, 69, 76, 83, 90):
                ns = f"string_acoustic_{split[-4:]}{k:02d}-{pitch:03d}-{(25 + 25 * (k % 4)):03d}"
                sf.write(os.path.join(d, "audio", ns + ".wav"), violin_like(rng, pitch), SR)
                ex[ns] = dict(instrument_str=f"string_acoustic_{split[-4:]}{k:02d}", instrument_family_str="string", instrument_source_str="acoustic", pitch=pitch,
                              velocity=25 + 25 * (k % 4), qualities_str=["fast_decay"] if k == 0 else [])
        json.dump(ex, open(os.path.join(d, "examples.json"), "w"))
    so = os.path.join(root, "src_so")
    ages, gens = [], []
    for s in range(12):
        sid = f"{s + 1:04d}"
        child = s < 6
        ages.append(f"{sid} {6 + s if child else 25 + s}")
        gens.append(f"{sid} {'m' if s % 2 else 'f'}")
        d = os.path.join(so, "WAVE", f"SPEAKER{sid}")
        os.makedirs(d)
        for u in range(3):
            sf.write(os.path.join(d, f"{sid}{u:05d}.WAV"), speech_like(rng, rng.uniform(2.5, 4), 250 if child else 110, 400 if child else 240), SR)
    os.makedirs(os.path.join(so, "train"))
    open(os.path.join(so, "train", "spk2age"), "w").write("\n".join(ages) + "\n")
    open(os.path.join(so, "train", "spk2gender"), "w").write("\n".join(gens) + "\n")
    mu = os.path.join(root, "src_mu", "musan", "noise", "free-sound")
    os.makedirs(mu)
    lic = []
    for k in range(3):
        nm = f"noise-free-sound-{k:04d}.wav"
        sf.write(os.path.join(mu, nm), (0.05 * rng.standard_normal(SR * 5)).astype(np.float32), SR)
        lic.append(f"{nm} licensed CC BY (stand-in)")
    open(os.path.join(mu, "LICENSE"), "w").write("\n".join(lic[:2]) + "\n")      # the third file has no entry: must be excluded


def sh(*args):
    r = subprocess.run([sys.executable] + list(args), cwd=HERE, capture_output=True, text=True)
    if r.returncode:
        print(r.stdout, r.stderr)
        raise SystemExit(f"FAILED: {' '.join(args)}")
    return r.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep")
    a = ap.parse_args()
    if not os.path.exists(FROZEN_CLI):
        raise SystemExit(f"needs the frozen CLI at {FROZEN_CLI}")
    root = a.keep or tempfile.mkdtemp(prefix="voice_selftest_")
    os.makedirs(root, exist_ok=True)
    rng = np.random.default_rng(7)
    build_corpora(root, rng)
    pub, mix = os.path.join(root, "public"), os.path.join(root, "mix")
    for c, src in (("librispeech", "src_ls"), ("nsynth", "src_ns"), ("speechocean762", "src_so"), ("musan", "src_mu")):
        out = sh("intake.py", c, "--dir", os.path.join(root, src), "--out", pub, "--allow-count-mismatch")
        print(out.strip().splitlines()[0])
    man = read_json(os.path.join(pub, "musan", "manifest.json"))
    assert sum(i["licence_entry_found"] for i in man["items"]) == 2, "MUSAN file without a LICENSE entry must be flagged"
    so = read_json(os.path.join(pub, "speechocean762", "manifest.json"))
    assert so["counts"]["children"] == 6 and so["counts"]["adults"] == 6, so["counts"]
    pools = os.path.join(root, "pools.json")
    sh("pools.py", "--public", pub, "--out", pools)
    P = read_json(pools)["groups"]
    for st, g in P.items():
        assert not set(g["dev"]) & set(g["sealed"]), f"pools overlap in {st}"
    h1 = sha256_file(pools)
    sh("pools.py", "--public", pub, "--out", pools)
    assert sha256_file(pools) == h1, "pools are not deterministic"
    assert any(g["sealed"] for g in P.values()), "no sealed ids at all"
    for seeds in ([9401],):
        sh("gen_mix.py", "--pool", "dev", "--seeds", *map(str, seeds), "--clips", "42", "--public", pub, "--pools", pools, "--out", mix)
    first, _ = sf.read(os.path.join(mix, sorted(f for f in os.listdir(mix) if f.endswith(".wav"))[0]))   # samples, not bytes: libsndfile's PEAK chunk holds a timestamp
    mix2 = os.path.join(root, "mix2")
    sh("gen_mix.py", "--pool", "dev", "--seeds", "9401", "--clips", "3", "--public", pub, "--pools", pools, "--out", mix2)
    again, _ = sf.read(os.path.join(mix2, sorted(f for f in os.listdir(mix2) if f.endswith(".wav"))[0]))
    assert first.shape == again.shape and np.array_equal(first, again), "generator is not deterministic"
    r = subprocess.run([sys.executable, "gen_mix.py", "--pool", "dev", "--seeds", "44001", "--public", pub, "--pools", pools], cwd=HERE, capture_output=True, text=True)
    assert r.returncode != 0, "a sealed seed must be refused for the dev pool"
    sealed_ids = {i for g in P.values() for i in g["sealed"]}
    used = set()
    for f in os.listdir(mix):
        if f.endswith(".json"):
            T = read_json(os.path.join(mix, f))
            if "notes" in T:
                used |= {n["instrument"] for n in T["notes"]} | {s["speaker"] for s in T["speech"]}
    assert not used & sealed_ids, "dev mixtures used a sealed id"
    npz = os.path.join(root, "dev.npz")
    sh("features.py", "--mix-dir", mix, "--out", npz)
    d = np.load(npz, allow_pickle=True)
    ok = d["voiced"].astype(bool) & (d["label"] >= 0)
    assert ok.sum() > 500, f"too few labelled voiced hops ({ok.sum()})"
    assert set(np.unique(d["label"][ok])) >= {0, 1}, "need both speech and violin labelled hops"
    for k in d["feature_names"]:
        v = d[k][ok]
        assert np.isfinite(v[~np.isnan(v)]).all() and np.nanmin(v) >= 0 and np.nanmax(v) <= 1, f"{k} outside [0,1]"
    model = os.path.join(root, "model.json")
    out = sh("fit.py", "--feats", npz, "--out", model, "--max-rows", "4000")
    print(out.strip())
    M = read_json(model)
    assert M["features"], "no feature selected"
    rep = sh("eval_gates.py", "mix", "--mix-dir", mix, "--out", os.path.join(root, "baseline.md"))
    assert "G1" in rep and "base notes/min" in rep
    rep2 = sh("eval_gates.py", "mix", "--mix-dir", mix, "--cli-new", FROZEN_CLI, "--out", os.path.join(root, "compare.md"))
    assert "G3" in rep2 and "recall" in rep2
    print(rep2.split("## G3")[1].split("\n")[3] if "## G3" in rep2 else "")
    print(f"SELFTEST OK ({root})")
    if not a.keep:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    main()
