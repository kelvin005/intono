"""Narrow-step sets (Kelechi, 2026-11-28), scale mode: (a) "realistic" scales, every note detuned 0 to 40 cents (sealed name p3real);
(b) "stress": every step 60 to 80 cents, notes played 20 to 40 cents flat or sharp (p3semi).
usage: python3 -I run_semitones.py --set realistic|stress --seeds 9561 9562 --cli PATH [--free]   (dev seeds 9561-9576)
       python3 -I run_semitones.py --sealed p3real|p3semi --cli FROZEN                            (once each, scale mode)
Generator and scoring: ref/semitone_set.py.
Gates: (a) recall >= 0.99 and invented <= 0.5 % of truth notes; (b) recall >= 0.97, invented reported (docs/adr/sealed-p3semi-preregistration.md)."""
import argparse, datetime, hashlib, io, subprocess, sys, tempfile
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).parent / "ref"))
import semitone_set as S
import synth

# Sealed sets: seeds and sha256 of "seed,seed,..." fixed before the set is run; a set runs once and is never reused.
SEALED = {
    # docs/adr/sealed-p3semi-preregistration.md. Registered 2026-11-28 before any clip of either set was generated. Refused until the
    # frozen-binary addendum to that file is written (after the DSP change, ADR 0018, is merged and the binary is built from the merge).
    "p3real": dict(seeds=list(range(34601, 34617)), sha="966768fd118e818c527d63c76d427ee4d4a70f40a8c5eae5ce856329b6871d15", kind="realistic",
                   spent=None, pending="the frozen-binary addendum to docs/adr/sealed-p3semi-preregistration.md is not written yet"),
    "p3semi": dict(seeds=list(range(34501, 34517)), sha="408e17b39cd9ae68342680819eea3777357da2e1c20cc96a2c02aad220f1e6b2", kind="stress",
                   spent=None, pending="the frozen-binary addendum to docs/adr/sealed-p3semi-preregistration.md is not written yet"),
}
DEV = range(9561, 9577)
# (a) realistic: recall >= 0.99 and invented <= 0.5 % of truth notes. (b) stress: recall >= 0.97 gated; invented reported, not gated.
GATES = {"realistic": {"recall": (">=", 0.99), "invented_rate": ("<=", 0.005)},
         "stress": {"recall": (">=", 0.97)}}
LOG = Path(__file__).parent / "reports/phase3/semitone_runs.log"


def notes_cli(cli, audio, expected):
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / "x.wav"
        sf.write(wav, audio, synth.SR, subtype="FLOAT")
        cmd = [cli, str(wav), "--notes", "1"] + (["--expected", ",".join(map(str, expected))] if expected else [])
        r = subprocess.run(cmd, capture_output=True, text=True, check=True)
    a = np.loadtxt(io.StringIO(r.stdout), delimiter=",", skiprows=1, ndmin=2)
    return [(q[0], int(q[2])) for q in a]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, nargs="+")
    ap.add_argument("--sealed", choices=list(SEALED))
    ap.add_argument("--cli", required=True)
    ap.add_argument("--set", choices=["stress", "realistic"], default="stress", help="dev: stress = every step 60-80 cents (b), realistic = (a)")
    ap.add_argument("--free", action="store_true", help="dev only: free mode, for comparison")
    a = ap.parse_args()
    if a.sealed:
        cfg = SEALED[a.sealed]
        if cfg.get("pending"):
            sys.exit(f"sealed set '{a.sealed}' is registered but cannot run yet: {cfg['pending']}")
        if cfg["spent"]:
            sys.exit(f"sealed set '{a.sealed}' is spent ({cfg['spent']})")
        if a.free:
            sys.exit("a sealed set runs in scale mode, as registered")
        if hashlib.sha256(",".join(map(str, cfg["seeds"])).encode()).hexdigest() != cfg["sha"]:
            sys.exit(f"{a.sealed} seed list does not match its registered hash")
        if LOG.exists() and any(f" set={a.sealed} " in line for line in LOG.read_text().splitlines()):
            sys.exit(f"sealed set '{a.sealed}' has already been run; a sealed set is never reused")
        seeds = cfg["seeds"]
        kind = cfg["kind"]
    else:
        if not a.seeds or any(s not in DEV for s in a.seeds):
            sys.exit(f"dev seeds only ({DEV.start}-{DEV.stop - 1}) on this entry point")
        seeds = a.seeds
        kind = a.set
    results = []
    for seed in seeds:
        for ph in (S.build_realistic_set(seed) if kind == "realistic" else S.build_semitone_set(seed)):
            results.append((ph, notes_cli(a.cli, ph.audio, None if a.free else [t["midi"] for t in ph.notes])))
    s = S.score(results)
    print(f"seeds {seeds} ({'free' if a.free else 'scale'} mode): {s['truth']} notes, {s['found']} found (recall {s['recall']:.4f}); "
          f"{s['invented']} invented (rate {s['invented_rate']:.4f}); 100-250 ms notes {s['short']}, recall {s['recall_short']:.4f}")
    ok = True
    if "invented_rate" not in GATES[kind]:
        print(f"  invented_rate  (not gated) {s['invented_rate']:.4f}")
    for k, (op, lim) in GATES[kind].items():
        good = s[k] <= lim if op == "<=" else s[k] >= lim
        ok &= bool(good)
        print(f"  {k:14s} {op} {lim:<6} got {s[k]:.4f}  {'PASS' if good else 'FAIL'}")
    if a.sealed:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with LOG.open("a") as f:
            f.write(f"{datetime.datetime.now().isoformat(timespec='seconds')} set={a.sealed} seeds={seeds} cli={a.cli} "
                    f"recall={s['recall']:.4f} invented_rate={s['invented_rate']:.4f} recall_short={s['recall_short']:.4f} pass={ok}\n")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
