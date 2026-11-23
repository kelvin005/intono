"""Short-run set (ADR 0004, Amendment 4): runs of 5-7 consecutive legato notes of 100-250 ms.
usage: python3 -I run_short_runs.py --seeds 9301 9302 [--cli PATH] [--cache DIR]
Dev seeds are 9xxx. Sealed seeds are registered in SEALED below and refused here: they run through --sealed NAME
once (the registry refuses a second run). Without --cli the Python mirror ref/stream_ref.py is used.
Gates (Amendment 4): recall >= 0.995 for notes >= 150 ms, >= 0.98 for 100-150 ms, <= 1 extra note per 200 notes."""
import argparse, io, subprocess, sys, tempfile
from pathlib import Path
import numpy as np
import soundfile as sf
sys.path.insert(0, str(Path(__file__).parent / "ref"))
import yin_ref, synth, stream_ref as S

# Sealed short-run sets: seeds and sha256 of "seed,seed,..." fixed before the set is run; a set runs once and is never reused.
SEALED = {
    "sr1": dict(seeds=list(range(34001, 34009)), sha="5068c7584ee40e263bb18b6c91077622e310d6c336c2cd901d0b78dd6136840a", spent=None,
                min_step=150.0, gated=True),   # reports/phase1/sealed_short_run_1.md
    # informational only (no gate): centre steps down to 100 cents, same generator; reports/phase1/sealed_short_run_1.md, addendum
    "sr1info": dict(seeds=list(range(34101, 34109)), sha="d0301ff2a0ae94da89ac43656cba03403fbbc7662ae8b6d05aeb7b9141e6e8b1", spent=None, min_step=100.0, gated=False),
}
GATES = {"recall_ge150": (">=", 0.995), "recall_100_150": (">=", 0.98), "extra_per_200": ("<=", 1.0)}
LOG = Path(__file__).parent / "reports/phase1/short_run_runs.log"


def notes_cli(cli, audio):
    with tempfile.TemporaryDirectory() as td:
        wav = Path(td) / "x.wav"
        sf.write(wav, audio, synth.SR, subtype="FLOAT")
        r = subprocess.run([cli, str(wav), "--notes", "1"], capture_output=True, text=True, check=True)
    a = np.loadtxt(io.StringIO(r.stdout), delimiter=",", skiprows=1, ndmin=2)
    return [(q[0], int(q[2])) for q in a]


def notes_mirror(audio):
    cfg = yin_ref.YinConfig(sample_rate=float(synth.SR))
    x = np.concatenate([audio, np.zeros(int(0.2 * synth.SR))])
    _, _, notes = S.run_stream(x, cfg)
    return [(n.t_start, n.midi_note) for n in notes]


def smaller_step_c(notes, i):
    """Smaller centre step (cents) to the neighbours of note i; inf for a single-note run."""
    out = [abs(100.0 * (notes[i]["midi"] - notes[j]["midi"]) + notes[i]["detune_c"] - notes[j]["detune_c"])
           for j in (i - 1, i + 1) if 0 <= j < len(notes)]
    return min(out) if out else float("inf")


def evaluate(seeds, cli=None, verbose=False, min_step_c=150.0, bands=None):
    tot = hit = extra = 0
    b = {"100-150": [0, 0], "150-200": [0, 0], ">=200": [0, 0]}
    for seed in seeds:
        for ph in synth.build_short_run_set(seed, min_step_c=min_step_c):
            est = notes_cli(cli, ph.audio) if cli else notes_mirror(ph.audio)
            used = set()
            for ti, t in enumerate(ph.notes):
                tot += 1
                d = t["t_off"] - t["t_on"]
                found = False
                for j, (t0, midi) in enumerate(est):
                    if j not in used and midi == t["midi"] and abs(t0 - t["t_on"]) < 0.08:
                        used.add(j); found = True; break
                hit += found
                if bands is not None:
                    st = smaller_step_c(ph.notes, ti)
                    bk = "step 100-130" if st < 130 else "step 130-150" if st < 150 else "step >=150"
                    bands.setdefault(bk, [0, 0]); bands[bk][0] += 1; bands[bk][1] += (not found)
                k = "100-150" if d < 0.15 else "150-200" if d < 0.20 else ">=200"
                b[k][0] += 1; b[k][1] += (not found)
                if verbose and not found:
                    print(f"  miss seed {seed} {ph.meta.get('name', '')} midi {t['midi']} t_on {t['t_on']:.3f} dur {d:.3f}")
            extra += len(est) - len(used)
    return tot, hit, extra, b


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, nargs="+")
    ap.add_argument("--sealed", choices=list(SEALED), help="run a registered sealed set (once; needs --cli)")
    ap.add_argument("--cli")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--min-step", type=float, default=150.0, help="smallest centre step in cents (gate scope: 150)")
    a = ap.parse_args()
    if a.sealed:
        import datetime, hashlib
        cfg = SEALED[a.sealed]
        if not a.cli:
            sys.exit("a sealed run needs --cli (the frozen binary)")
        if cfg["spent"]:
            sys.exit(f"sealed set '{a.sealed}' is spent ({cfg['spent']})")
        if hashlib.sha256(",".join(map(str, cfg["seeds"])).encode()).hexdigest() != cfg["sha"]:
            sys.exit(f"{a.sealed} seed list does not match its registered hash")
        if LOG.exists() and any(f" set={a.sealed} " in line for line in LOG.read_text().splitlines()):
            sys.exit(f"sealed set '{a.sealed}' has already been run; a sealed set is never reused")
        seeds, min_step = cfg["seeds"], cfg["min_step"]
    else:
        if not a.seeds:
            sys.exit("give --seeds (dev, 9000-9999) or --sealed NAME")
        for s_ in a.seeds:
            if not 9000 <= s_ < 10000:
                sys.exit("dev seeds only (9000-9999) on this entry point")
        seeds, min_step = a.seeds, a.min_step
    gated = not a.sealed or SEALED[a.sealed]["gated"]
    bands = None if gated else {}
    tot, hit, extra, b = evaluate(seeds, a.cli, a.verbose, min_step, bands)
    ge150 = [sum(b[k][0] for k in (">=200", "150-200")), sum(b[k][1] for k in (">=200", "150-200"))]
    res = {"recall_ge150": 1 - ge150[1] / ge150[0], "recall_100_150": 1 - b["100-150"][1] / max(b["100-150"][0], 1),
           "extra_per_200": 200 * extra / tot}
    print(f"seeds {seeds}: truth notes {tot}, recovered {hit} (recall {hit / tot:.4f}), extra notes {extra} ({res['extra_per_200']:.2f} per 200)")
    for k, (n, miss) in b.items():
        print(f"  {k} ms: {n} notes, {miss} missed, recall {1 - miss / max(n, 1):.4f}")
    if not gated:
        print("  informational, no gate: recall by the smaller adjacent centre step")
        for k, (n, miss) in sorted(bands.items()):
            print(f"    {k} cents: {n} notes, {miss} missed, recall {1 - miss / max(n, 1):.4f}")
    ok = True
    for k, (op, lim) in (GATES.items() if gated else []):
        good = res[k] >= lim if op == ">=" else res[k] <= lim
        ok &= bool(good)
        print(f"  {k:16s} {op} {lim:<6} got {res[k]:.4f}  {'PASS' if good else 'FAIL'}")
    if a.sealed:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with LOG.open("a") as f:
            f.write(f"{datetime.datetime.now().isoformat(timespec='seconds')} set={a.sealed} seeds={seeds} cli={a.cli} " + " ".join(f"{k}={v:.4f}" for k, v in res.items())
                    + (f" pass={ok}" if gated else " informational") + (" bands=" + ";".join(f"{k}:{n}/{m}" for k, (n, m) in sorted(bands.items())) if bands else "") + "\n")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
