"""Note-boundary gate (ADR 0004): legato steps >= 60 c under wide vibrato, and false splits on steady wide vibrato.

    python run_boundaries.py --cli /path/to/intono-cli --seeds dev     # development: tune against these freely
    python run_boundaries.py --cli /path/to/intono-cli --seeds gate3   # sealed set 3 (pre-registered in reports/phase1/sealed_set_3.md)

Sealed sets (SEALED below): "gate" and "gate2" are spent. A set is run once on a frozen binary; the script refuses a second
run, verifies the seed list against its pre-registered hash, and appends every run to reports/phase1/gate_runs.log.
A failed set is never reused: fix on dev seeds (more of them can be used: any seed not in SEALED) and register a new set.

Gate (all on the sealed seeds, never the dev seeds):
  recall and precision of step boundaries >= 0.995 for steps >= 60 c, vibrato up to +-50 c at 4-8 Hz, 16 phases;
  0 false splits on steady wide vibrato;
  boundary time error |t_start - true step|: p95 <= 20 ms and max <= 100 ms;
  note-mean error caused by the boundaries: |reported mean - reference mean| <= 2 c on every note, median <= 0.5 c,
    where the reference is the mean of the same raw pitch track over the true note interval, leaving out the 30 ms
    guard zone at the true boundary and the same run-start / run-end trims the engine applies (first 6 voiced frames
    of a run, last 3), so that only what the boundary placement causes is measured;
  summary delay (note emitted - true boundary) <= 350 ms.
Exit code 1 if a gate is missed.
"""
from __future__ import annotations

import argparse
import datetime
import io
import subprocess
import sys
import pickle
import tempfile
from collections import defaultdict
from pathlib import Path

import numpy as np
import soundfile as sf

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "ref"))
import synth  # noqa: E402
import yin_ref  # noqa: E402

DEV_SEEDS = [9101, 9102]
GATE_SEEDS = [31001, 31002, 31003, 31004]   # fixed before any HMM code existed; not used for tuning. SPENT.
# Sealed sets: seeds and sha256 of "seed,seed,..." fixed before the set is run; a set runs once and is never reused.
SEALED = {
    "gate": dict(seeds=GATE_SEEDS, sha=None, spent="passed once, on the version before ADR 0004 Amendment 2"),
    "gate2": dict(seeds=[32001, 32002, 32003, 32004], sha="c8a8980b6e3cf9d0851e49733dd8be872d180b604ca4b9e61c5a0041ca5c0aaf",
                  spent="FAILED 2026-11-22 (note-mean error max 2.32 c); see reports/phase1/sealed_set_2.md"),
    "gate3": dict(seeds=[33001, 33002, 33003, 33004], sha="21227fc7aa2402f357d9a63d28db213abade1d49f2b3e98651dc11a2f2868677",
                  spent="PASSED 2026-11-22 (ADR 0004 with Amendments 2 and 3); see reports/phase1/sealed_set_3.md"),
    "gate4": dict(seeds=[35001, 35002, 35003, 35004], sha="7754b293e40a7925b0f8205810b8e39bc476be05335e29cbb0c17a799b50b58f", spent=None),   # reports/phase1/sealed_set_4.md (ADR 0004 Amendment 4)
}
N_STEP, N_STEADY = 150, 60
GATES = {"recall": (">=", 0.995), "precision": (">=", 0.995), "false_splits_steady": ("==", 0),
         "boundary_err_ms_p95": ("<=", 20.0), "boundary_err_ms_max": ("<=", 100.0),
         "note_mean_err_c_max": ("<=", 2.0), "note_mean_err_c_median": ("<=", 0.5), "delay_ms_max": ("<=", 350.0)}
GUARD_S, HEAD_FRAMES, END_FRAMES = 0.030, 6, 3


def run_notes(cli, wav):
    r = subprocess.run([cli, str(wav), "--notes", "1"], capture_output=True, text=True, check=True)
    a = np.loadtxt(io.StringIO(r.stdout), delimiter=",", skiprows=1, ndmin=2)
    return [dict(t0=q[0], t1=q[1], midi=int(q[2]), cents=q[3], frames=int(q[8]), emit=q[9]) for q in a]


def note_mean_errors(ph, est, j):
    """Reported mean (cents re 440) minus the reference mean over the true interval, for the matched notes A and B."""
    r = yin_ref.analyse(ph.audio)
    t, ok = np.asarray(r.t), np.asarray(r.voiced, dtype=bool) & (np.asarray(r.hz) > 0)
    c = np.zeros(len(t))
    c[ok] = 1200 * np.log2(np.asarray(r.hz)[ok] / 440.0)
    t_step = ph.meta["t_step"]
    a_i = [k for k, q in enumerate(est) if q["midi"] == ph.notes[0]["midi"] and abs(q["t0"] - ph.notes[0]["t_on"]) <= 0.15]
    cases = []
    if a_i:   # A: run start (6 voiced frames skipped), true boundary on the right
        idx = np.flatnonzero(ok & (t >= ph.notes[0]["t_on"] - 0.02) & (t < t_step - GUARD_S))
        cases.append((est[a_i[0]], idx[HEAD_FRAMES:]))
    idx = np.flatnonzero(ok & (t >= t_step + GUARD_S) & (t <= ph.notes[1]["t_off"]))   # B: true boundary on the left, run end
    cases.append((est[j], idx[: max(len(idx) - END_FRAMES, 0)]))
    return [100 * (e["midi"] - 69) + e["cents"] - c[sel].mean() for e, sel in cases if len(sel) >= 5]


def score_step(ph, est):
    g = ph.notes
    t_step, mB = ph.meta["t_step"], g[1]["midi"]
    det = [j for j, e in enumerate(est) if e["midi"] == mB and abs(e["t0"] - t_step) <= 0.1]
    j = det[0] if det else None
    # A is the one note that starts within 60 ms of the true onset (the first voiced frame is ~25 ms late); every other
    # note except the detected B is spurious. (Until 2026-11-22 the window was 150 ms, which hid a fake note split off
    # the start of the first note; found after sealed set 2 failed, so sealed set 1 and 2 numbers used the wide window.)
    a_i = [k for k, e in enumerate(est) if abs(e["t0"] - g[0]["t_on"]) <= 0.06]
    spurious = sum(1 for k, e in enumerate(est) if k != j and k not in a_i[:1])
    out = dict(detected=j is not None, spurious=spurious)
    if j is not None:
        out["err_ms"] = 1000 * (est[j]["t0"] - t_step)
        out["mean_errs"] = note_mean_errors(ph, est, j)
        if j >= 1:
            out["delay_ms"] = 1000 * (est[j - 1]["emit"] - t_step)
    return out


def clips_for(seed, cache):
    f = Path(cache) / f"clips_{seed}.pkl" if cache else None
    if f and f.exists():
        return pickle.loads(f.read_bytes())
    data = (synth.build_boundary_set(seed, N_STEP), synth.build_steady_vibrato_set(seed, N_STEADY))
    if f:
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(pickle.dumps(data))
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cli", required=True)
    ap.add_argument("--seeds", choices=["dev"] + list(SEALED), required=True)
    ap.add_argument("--cache", help="directory for the synthesized clips (they depend only on the seeds); speeds up sweeps")
    args = ap.parse_args()
    log = HERE / "reports/phase1/gate_runs.log"
    if args.seeds in SEALED:
        import hashlib
        cfg = SEALED[args.seeds]
        if cfg["spent"]:
            sys.exit(f"sealed set '{args.seeds}' is spent ({cfg['spent']}); use dev seeds or the next registered sealed set")
        if hashlib.sha256(",".join(map(str, cfg["seeds"])).encode()).hexdigest() != cfg["sha"]:
            sys.exit(f"{args.seeds} seed list does not match its registered hash")
        if log.exists() and any(f" set={args.seeds} " in line for line in log.read_text().splitlines()):
            sys.exit(f"sealed set '{args.seeds}' has already been run; a sealed set is never reused")
    seeds = DEV_SEEDS if args.seeds == "dev" else SEALED[args.seeds]["seeds"]
    rows, steady_splits, steady_missing, n_steady = [], 0, 0, 0
    buckets = defaultdict(lambda: [0, 0])
    with tempfile.TemporaryDirectory() as td:
        for seed in seeds:
            step_clips, steady_clips = clips_for(seed, args.cache)
            for ph in step_clips:
                wav = Path(td) / "x.wav"
                sf.write(wav, ph.audio, synth.SR, subtype="FLOAT")
                s = score_step(ph, run_notes(args.cli, wav))
                rows.append(s)
                vib = ph.notes[0]["vib_pp_c"] > 0 or ph.notes[1]["vib_pp_c"] > 0
                b = ("vib" if vib else "plain", "step<80" if abs(ph.meta["step_c"]) < 80 else "step>=80")
                buckets[b][0] += s["detected"]
                buckets[b][1] += 1
            for ph in steady_clips:
                wav = Path(td) / "x.wav"
                sf.write(wav, ph.audio, synth.SR, subtype="FLOAT")
                est = run_notes(args.cli, wav)
                n_steady += 1
                steady_splits += max(0, len(est) - 1)
                steady_missing += int(len(est) == 0)
    det = sum(r["detected"] for r in rows)
    spur = sum(r["spurious"] for r in rows)
    err = np.array([abs(r["err_ms"]) for r in rows if "err_ms" in r] or [np.nan])
    merr = np.abs(np.array([e for r in rows for e in r.get("mean_errs", [])] or [np.nan]))
    dly = np.array([r["delay_ms"] for r in rows if "delay_ms" in r] or [np.nan])
    res = {"recall": det / len(rows), "precision": det / max(det + spur, 1), "false_splits_steady": steady_splits,
           "boundary_err_ms_p95": float(np.nanpercentile(err, 95)), "boundary_err_ms_max": float(np.nanmax(err)),
           "note_mean_err_c_max": float(np.nanmax(merr)), "note_mean_err_c_median": float(np.nanmedian(merr)),
           "delay_ms_max": float(np.nanmax(dly))}
    print(f"seeds {seeds} ({args.seeds}): {len(rows)} step clips, {n_steady} steady-vibrato clips; spurious extra notes {spur}; "
          f"steady clips with no note {steady_missing}")
    print(f"boundary error ms: median {np.nanmedian(err):.1f} p95 {np.nanpercentile(err, 95):.1f} max {np.nanmax(err):.1f}; "
          f"delay ms: median {np.nanmedian(dly):.0f} max {np.nanmax(dly):.0f}; "
          f"note-mean error c: median {np.nanmedian(merr):.2f} p95 {np.nanpercentile(merr, 95):.2f} max {np.nanmax(merr):.2f} (n={int(np.isfinite(merr).sum())})")
    for k, (d, n) in sorted(buckets.items()):
        print(f"  recall {k[0]:5s} {k[1]:9s}: {d}/{n} = {d / n:.3f}")
    ok = True
    for k, (op, lim) in GATES.items():
        v = res[k]
        good = {">=": v >= lim, "<=": v <= lim, "==": v == lim}[op]
        ok &= bool(good)
        print(f"  {k:22s} {op} {lim:<6} got {v:8.3f}  {'PASS' if good else 'FAIL'}")
    if args.seeds in SEALED:
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("a") as f:
            f.write(f"{datetime.datetime.now().isoformat(timespec='seconds')} set={args.seeds} seeds={seeds} cli={args.cli} " + " ".join(f"{k}={v:.4f}" for k, v in res.items()) + f" pass={ok}\n")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
