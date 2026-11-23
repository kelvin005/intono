#!/usr/bin/env python3
"""Byte-for-byte comparison of two intono-cli builds on the same audio (frames and notes).

  diff_cli.py --a /tmp/frozen/intono-cli-gate4 --b /tmp/b4/intono-cli [--seeds 21 77 123 2024] [--real PATH] [--pad 3]

Used for ADR 0008: the denormal flush (Amendment 1) and the worker thread must change no output. Every clip is also run with `--pad` seconds
of digital silence appended (the denormal case). Exit code 1 on any difference.
"""
import argparse
import os
import subprocess
import sys
import tempfile

import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "ref"))
import synth  # noqa: E402


def run(cli, wav, notes, extra=""):
    args = [cli, wav] + (["--notes", "1"] if notes else []) + extra.split()
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--a", required=True)
    ap.add_argument("--b", required=True)
    ap.add_argument("--seeds", type=int, nargs="*", default=[21, 77, 123, 2024])
    ap.add_argument("--real")
    ap.add_argument("--a-args", default="", help="extra CLI arguments for A, e.g. '--threaded 1 --stall 3000'")
    ap.add_argument("--b-args", default="")
    ap.add_argument("--pad", type=float, default=3.0)
    ap.add_argument("--limit", type=int, default=0, help="max clips per seed (0 = all)")
    a = ap.parse_args()
    clips = []
    for s in a.seeds:
        ph = synth.build_phrase_set(s)
        clips += [(f"phrase{s}/{p.name}", p.audio.astype(np.float32), synth.SR) for p in (ph[:a.limit] if a.limit else ph)]
    if a.real:
        x, sr = sf.read(a.real, dtype="float32")
        clips.append(("real", x if x.ndim == 1 else x[:, 0], sr))
    bad = n = 0
    with tempfile.TemporaryDirectory() as td:
        for name, x, sr in clips:
            for tag, y in (("", x), ("+pad", np.concatenate([x, np.zeros(int(a.pad * sr), np.float32)]))):
                w = os.path.join(td, "c.wav")
                sf.write(w, y, sr, subtype="FLOAT")
                for notes in (False, True):
                    n += 1
                    ra, rb = run(a.a, w, notes, a.a_args), run(a.b, w, notes, a.b_args)
                    if ra != rb:
                        bad += 1
                        la, lb = ra.splitlines(), rb.splitlines()
                        k = next((i for i, (p, q) in enumerate(zip(la, lb)) if p != q), min(len(la), len(lb)))
                        print(f"DIFF {name}{tag} notes={notes}: line {k}: {la[k] if k < len(la) else '-'} | {lb[k] if k < len(lb) else '-'}")
    print(f"{n} comparisons, {bad} differ")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
