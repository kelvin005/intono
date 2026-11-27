"""Deviation set (ADR 0014, second sealed gate): does score-informed segmentation INVENT the expected note when the player deviates?
usage: python3 -I run_deviations.py --seeds 9521 9522 --cli PATH        (dev seeds 9521-9536)
       python3 -I run_deviations.py --sealed p3dev --cli FROZEN          (once)
Each phrase's expected sequence is passed to the engine (intono-cli --expected m1,m2,...). Generator and scoring: ref/deviation_set.py.
Gates (Kelechi, 2026-11-27): invented-expected-note rate <= 0.005 of deviations; recall of the played deviation notes >= 0.98."""
import argparse, datetime, hashlib, io, subprocess, sys, tempfile
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).parent / "ref"))
import deviation_set as D
import synth

# Sealed deviation sets: seeds and sha256 of "seed,seed,..." fixed before the set is run; a set runs once and is never reused.
SEALED = {
    # docs/adr/sealed-p3gate-preregistration.md, section "p3dev". Registered 2026-11-27 before any implementation; refused until the
    # engine and the CLI take an expected sequence (ADR 0014 implementation).
    "p3dev": dict(seeds=list(range(34301, 34317)), sha="6c44e218bb711a378ec6c0faf9d89ee4b3c8e5966f80fb370a8762b6ebbde295", spent=None,
                  pending="intono-cli --expected (ADR 0014 implementation) is not written yet"),
}
DEV = range(9521, 9537)
GATES = {"invented_rate": ("<=", 0.005), "recall": (">=", 0.98)}
LOG = Path(__file__).parent / "reports/phase3/deviation_runs.log"


def notes_cli(cli, audio, expected):
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / "x.wav"
        sf.write(wav, audio, synth.SR, subtype="FLOAT")
        r = subprocess.run([cli, str(wav), "--notes", "1", "--expected", ",".join(map(str, expected))],
                           capture_output=True, text=True, check=True)
    a = np.loadtxt(io.StringIO(r.stdout), delimiter=",", skiprows=1, ndmin=2)
    return [(q[0], int(q[2])) for q in a]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, nargs="+")
    ap.add_argument("--sealed", choices=list(SEALED))
    ap.add_argument("--cli", required=True)
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    if a.sealed:
        cfg = SEALED[a.sealed]
        if cfg.get("pending"):
            sys.exit(f"sealed set '{a.sealed}' is registered but cannot run yet: {cfg['pending']}")
        if cfg["spent"]:
            sys.exit(f"sealed set '{a.sealed}' is spent ({cfg['spent']})")
        if hashlib.sha256(",".join(map(str, cfg["seeds"])).encode()).hexdigest() != cfg["sha"]:
            sys.exit(f"{a.sealed} seed list does not match its registered hash")
        if LOG.exists() and any(f" set={a.sealed} " in line for line in LOG.read_text().splitlines()):
            sys.exit(f"sealed set '{a.sealed}' has already been run; a sealed set is never reused")
        seeds = cfg["seeds"]
    else:
        if not a.seeds or any(s not in DEV for s in a.seeds):
            sys.exit(f"dev seeds only ({DEV.start}-{DEV.stop - 1}) on this entry point")
        seeds = a.seeds
    results = []
    for seed in seeds:
        for ph, E, ev in D.build_deviation_set(seed):
            est = notes_cli(a.cli, ph.audio, E)
            results.append((ph, E, ev, est))
            if a.verbose:
                t0, t1 = ev["window"]
                if any(m == ev["invented_midi"] and t0 <= t <= t1 for t, m in est):
                    print(f"  invented: seed {seed} {ph.meta.get('name', '')} {ev['kind']} midi {ev['invented_midi']}")
    s = D.score(results)
    print(f"seeds {seeds}: deviations {s['deviations']}, invented {s['invented']} (rate {s['invented_rate']:.4f}); "
          f"played deviation notes {s['played']}, found {s['found']} (recall {s['recall']:.4f})")
    for k, (n, inv, pl, fd) in s["by_kind"].items():
        print(f"  {k:9s} {n} deviations, {inv} invented, {pl} played, {fd} found")
    ok = True
    for k, (op, lim) in GATES.items():
        good = s[k] <= lim if op == "<=" else s[k] >= lim
        ok &= bool(good)
        print(f"  {k:14s} {op} {lim:<6} got {s[k]:.4f}  {'PASS' if good else 'FAIL'}")
    if a.sealed:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with LOG.open("a") as f:
            f.write(f"{datetime.datetime.now().isoformat(timespec='seconds')} set={a.sealed} seeds={seeds} cli={a.cli} "
                    f"invented_rate={s['invented_rate']:.4f} recall={s['recall']:.4f} pass={ok}\n")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
