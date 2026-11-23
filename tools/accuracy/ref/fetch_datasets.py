"""Prepare public violin datasets for the Phase 0 / harness runs.

Output layout (what run_baseline.py --wav-dir expects):
    data/prepared/<set>/<id>.wav        mono, 48 kHz, float
    data/prepared/<set>/<id>.f0.csv     time_s,hz   (hz = 0 when unvoiced)

Sets:
  nsynth  Downloads the NSynth test split (~340 MB) and keeps acoustic string
          notes in G3..E7. Labels are the nominal MIDI pitch only (ET, A4=440),
          so use NSynth for gross/octave errors, NOT for cents MAE.
  urmp    Point --urmp-dir at an already-downloaded URMP folder. Uses the
          per-track violin stems (AuSep_*_vn_*.wav) and their F0 files
          (F0s_*_vn_*.txt). URMP F0 labels were made with pYIN plus manual
          correction, so cents scores are biased slightly toward pYIN.

Licences: check NSynth (CC BY 4.0) and URMP terms before any commercial use
(architecture doc: ask Kelechi before deciding any dataset licence question).

Usage:
    python fetch_datasets.py nsynth [--out data/prepared]
    python fetch_datasets.py urmp --urmp-dir /path/to/URMP [--out data/prepared]
"""
from __future__ import annotations

import argparse
import json
import tarfile
import urllib.request
from math import gcd
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly

TARGET_SR = 48000
NSYNTH_URL = "http://download.magenta.tensorflow.org/datasets/nsynth/nsynth-test.jsonwav.tar.gz"
MIDI_LO, MIDI_HI = 55, 100          # G3..E7


def to_48k(x: np.ndarray, sr: int) -> np.ndarray:
    if x.ndim > 1:
        x = x.mean(axis=1)
    if sr == TARGET_SR:
        return x.astype(np.float32)
    g = gcd(sr, TARGET_SR)
    return resample_poly(x, TARGET_SR // g, sr // g).astype(np.float32)


def write_pair(out_dir: Path, ident: str, audio: np.ndarray, t: np.ndarray, hz: np.ndarray):
    out_dir.mkdir(parents=True, exist_ok=True)
    sf.write(out_dir / f"{ident}.wav", audio, TARGET_SR, subtype="FLOAT")
    np.savetxt(out_dir / f"{ident}.f0.csv", np.column_stack([t, hz]), delimiter=",",
               header="time_s,hz", comments="", fmt="%.6f")


def prep_nsynth(out: Path, cache: Path):
    cache.mkdir(parents=True, exist_ok=True)
    tgz = cache / "nsynth-test.jsonwav.tar.gz"
    if not tgz.exists():
        print(f"downloading {NSYNTH_URL}")
        urllib.request.urlretrieve(NSYNTH_URL, tgz)
    with tarfile.open(tgz) as tf:
        meta_member = next(m for m in tf.getmembers() if m.name.endswith("examples.json"))
        meta = json.load(tf.extractfile(meta_member))
        keep = {k: v for k, v in meta.items()
                if v["instrument_family_str"] == "string" and v["instrument_source_str"] == "acoustic"
                and MIDI_LO <= v["pitch"] <= MIDI_HI}
        print(f"keeping {len(keep)} acoustic string notes in G3..E7")
        members = {Path(m.name).stem: m for m in tf.getmembers() if m.name.endswith(".wav")}
        n = 0
        for k, v in keep.items():
            m = members.get(k)
            if m is None:
                continue
            x, sr = sf.read(tf.extractfile(m))
            y = to_48k(x, sr)
            hop = 256 / TARGET_SR
            t = np.arange(0, len(y) / TARGET_SR, hop)
            hz = np.where((t > 0.10) & (t < 2.9), 440.0 * 2 ** ((v["pitch"] - 69) / 12), 0.0)
            write_pair(out / "nsynth", k, y, t, hz)
            n += 1
    print(f"wrote {n} NSynth pairs to {out/'nsynth'}")


def prep_urmp(out: Path, urmp_dir: Path):
    n = 0
    for wav in sorted(urmp_dir.rglob("AuSep_*_vn_*.wav")):
        f0txt = wav.with_name(wav.name.replace("AuSep_", "F0s_").replace(".wav", ".txt"))
        if not f0txt.exists():
            print(f"no F0 file for {wav.name}, skipping")
            continue
        x, sr = sf.read(wav)
        y = to_48k(x, sr)
        lab = np.loadtxt(f0txt)
        write_pair(out / "urmp", wav.stem, y, lab[:, 0], lab[:, 1])
        n += 1
    print(f"wrote {n} URMP violin stems to {out/'urmp'}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("set", choices=["nsynth", "urmp"])
    ap.add_argument("--out", default="data/prepared")
    ap.add_argument("--cache", default="data/cache")
    ap.add_argument("--urmp-dir")
    a = ap.parse_args()
    if a.set == "nsynth":
        prep_nsynth(Path(a.out), Path(a.cache))
    else:
        if not a.urmp_dir:
            ap.error("urmp needs --urmp-dir pointing at the downloaded dataset")
        prep_urmp(Path(a.out), Path(a.urmp_dir))


if __name__ == "__main__":
    main()
