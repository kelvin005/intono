#!/usr/bin/env python3
"""Bit-identity against stored phase1-complete outputs (ADR 0009 answer 4, Note 4).

  golden.py make  --cli FROZEN/intono-cli --out tools/accuracy/golden/phase1-complete.json --source "phase1-complete e58070b"
  golden.py check --cli build/intono-cli --golden tools/accuracy/golden/phase1-complete.json [--threaded] [--jobs 16]

The synthetic dev corpus is the one diff_cli.py uses: every phrase set for the seeds, each clip as it is and with --pad seconds of digital
silence appended (the denormal case), frames mode and notes mode. For each case the manifest stores the SHA-256 of the float32 input
samples and of the CLI's stdout. `make` runs the frozen binary inline and through the worker thread and refuses to write a manifest if
the two differ, so one manifest checks both modes. `check` reads the seeds, pad and phrase limit from the manifest (they cannot drift
from what was recorded) and exits 1 on any difference:

  DIFF         the CLI output differs from the recorded output: a real change. Run diff_cli.py against a build of phase1-complete to
               see the first differing line.
  INPUT DRIFT  the synthetic input itself differs (a numpy/scipy change in synth.py's generation): the test is invalid, not failed by
               the DSP. Pin the versions recorded in the manifest's "env", or regenerate from the tag (dsp.yml, golden-provenance).

The threaded CLI waits for the worker after every chunk (the 2 ms poll, ADR 0008), so a threaded run takes about as long as the audio.
It is sleep-bound, not CPU-bound, hence --jobs well above the core count.
"""
import argparse
import hashlib
import json
import os
import platform
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import scipy
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "ref"))
import synth  # noqa: E402

FORMAT = 1


def corpus(seeds, pad, limit):
    """[(name, padded, samples float32, sr)] in a fixed order."""
    out = []
    for s in seeds:
        ph = synth.build_phrase_set(s)
        for p in (ph[:limit] if limit else ph):
            x = p.audio.astype(np.float32)
            out.append((f"phrase{s}/{p.name}", False, x, synth.SR))
            out.append((f"phrase{s}/{p.name}", True, np.concatenate([x, np.zeros(int(pad * synth.SR), np.float32)]), synth.SR))
    return out


def sha(b):
    return hashlib.sha256(b).hexdigest()


def run_case(cli, wav, notes, threaded):
    args = [cli, wav] + (["--notes", "1"] if notes else []) + (["--threaded", "1"] if threaded else [])
    return sha(subprocess.run(args, capture_output=True, check=True).stdout)


def hash_outputs(cli, cases, threaded, jobs, td):
    """{(i, mode): sha} for every case and mode, run in parallel."""
    paths = []
    for i, (_, _, x, sr) in enumerate(cases):
        w = os.path.join(td, f"c{i}.wav")
        sf.write(w, x, sr, subtype="FLOAT")
        paths.append(w)
    tasks = [(i, mode) for i in range(len(cases)) for mode in ("frames", "notes")]
    with ThreadPoolExecutor(max_workers=jobs) as ex:
        res = ex.map(lambda t: run_case(cli, paths[t[0]], t[1] == "notes", threaded), tasks)
        return dict(zip(tasks, res))


def make(a):
    cases = corpus(a.seeds, a.pad, a.limit)
    with tempfile.TemporaryDirectory() as td:
        inline = hash_outputs(a.cli, cases, False, a.jobs, td)
        threaded = hash_outputs(a.cli, cases, True, a.jobs, td)
    bad = [k for k in inline if inline[k] != threaded[k]]
    if bad:
        for i, mode in bad:
            print(f"inline != threaded on the source binary: {cases[i][0]}{'+pad' if cases[i][1] else ''} {mode}")
        sys.exit(1)
    m = {
        "format": FORMAT,
        "source": a.source,
        "generator": "tools/accuracy/golden.py make",
        "env": {"python": platform.python_version(), "numpy": np.__version__, "scipy": scipy.__version__,
                "machine": platform.machine(), "system": platform.system()},
        "seeds": a.seeds, "pad_s": a.pad, "limit": a.limit,
        "cases": [{"clip": n, "pad": p, "input_sha256": sha(x.tobytes()),
                   "out": {mode: inline[(i, mode)] for mode in ("frames", "notes")}}
                  for i, (n, p, x, _) in enumerate(cases)],
    }
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w") as f:
        json.dump(m, f, indent=1)
        f.write("\n")
    print(f"wrote {a.out}: {len(cases)} cases x 2 modes, inline == threaded")


def check(a):
    with open(a.golden) as f:
        m = json.load(f)
    if m.get("format") != FORMAT:
        sys.exit(f"unknown manifest format {m.get('format')}")
    cases = corpus(m["seeds"], m["pad_s"], m["limit"])
    if len(cases) != len(m["cases"]):
        sys.exit(f"manifest has {len(m['cases'])} cases, the corpus {len(cases)}: regenerate the manifest")
    drift = 0
    for (n, p, x, _), g in zip(cases, m["cases"]):
        if (n, p) != (g["clip"], g["pad"]):
            sys.exit(f"case order differs at {n}: regenerate the manifest")
        if sha(x.tobytes()) != g["input_sha256"]:
            drift += 1
            print(f"INPUT DRIFT {n}{'+pad' if p else ''}: the synthetic input differs from the recorded one")
    if drift:
        print(f"{drift} inputs drifted (recorded env {m['env']}, here numpy {np.__version__} scipy {scipy.__version__}): "
              "the comparison is invalid, not failed")
        sys.exit(1)
    with tempfile.TemporaryDirectory() as td:
        got = hash_outputs(a.cli, cases, a.threaded, a.jobs, td)
    bad = 0
    for i, g in enumerate(m["cases"]):
        for mode in ("frames", "notes"):
            if got[(i, mode)] != g["out"][mode]:
                bad += 1
                print(f"DIFF {g['clip']}{'+pad' if g['pad'] else ''} {mode}: {got[(i, mode)][:12]} != recorded {g['out'][mode][:12]}")
    n = 2 * len(cases)
    print(f"{n} comparisons ({'threaded' if a.threaded else 'inline'}) against {m['source']}, {bad} differ")
    sys.exit(1 if bad else 0)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    mk = sub.add_parser("make")
    mk.add_argument("--cli", required=True)
    mk.add_argument("--out", required=True)
    mk.add_argument("--source", required=True, help='what the CLI was built from, e.g. "phase1-complete e58070b"')
    mk.add_argument("--seeds", type=int, nargs="*", default=[21, 77, 123, 2024])
    mk.add_argument("--pad", type=float, default=3.0)
    mk.add_argument("--limit", type=int, default=0, help="max phrases per seed (0 = all)")
    mk.add_argument("--jobs", type=int, default=16)
    ck = sub.add_parser("check")
    ck.add_argument("--cli", required=True)
    ck.add_argument("--golden", required=True)
    ck.add_argument("--threaded", action="store_true", help="run the CLI through the worker thread (--threaded 1)")
    ck.add_argument("--jobs", type=int, default=16)
    a = ap.parse_args()
    make(a) if a.cmd == "make" else check(a)


if __name__ == "__main__":
    main()
