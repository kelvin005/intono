"""Phase 0 baseline: plain YIN (spec parameters) vs librosa pYIN.

Usage:
    python run_baseline.py [--out reports/phase0] [--no-pyin] [--wav-dir DIR]

Writes report.json and report.md. With --wav-dir, also scores real recordings
prepared by fetch_datasets.py (wav + .f0.csv label pairs).
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import metrics  # noqa: E402
import synth  # noqa: E402
import yin_ref  # noqa: E402

GATE_MAE = 5.0


def run_yin(clip, cfg):
    t0 = time.perf_counter()
    r = yin_ref.analyse(clip.audio, cfg)
    dt = time.perf_counter() - t0
    return r.t, r.hz, r.hz_centre, r.voiced, dt / max(len(r.t), 1)


def run_pyin(clip, cfg):
    import librosa
    t0 = time.perf_counter()
    f0, vflag, _ = librosa.pyin(
        clip.audio.astype(np.float64), fmin=cfg.min_hz, fmax=cfg.max_hz, sr=int(cfg.sample_rate),
        frame_length=cfg.window_size, hop_length=cfg.hop_size, center=False,
        # librosa default 0.1 = 10-cent bins, which handicaps the baseline. 0.01 (1-cent bins)
        # was tried and makes librosa 1.0.1 return no voiced frames at all, so use 0.02.
        resolution=0.02,
    )
    dt = time.perf_counter() - t0
    hz = np.nan_to_num(f0, nan=0.0)
    voiced = vflag.astype(bool) & (hz > 0)
    hz_c, _, _ = yin_ref.centre_pitch(hz, voiced, cfg)   # same display stage for fairness
    t = (np.arange(len(hz)) * cfg.hop_size + cfg.window_size / 2) / cfg.sample_rate
    return t, hz, hz_c, voiced, dt / max(len(t), 1)


def group_of(name):
    return name.split("_", 1)[1]


def score_wav_dir(wav_dir: Path, detectors, cfg):
    """Score labelled real recordings (pairs made by fetch_datasets.py).

    Frame labels come from <id>.f0.csv (time_s,hz). Only frames with a label
    (hz > 0) are scored; cents error is instantaneous (no vibrato centring),
    so vibrato-heavy real audio will show larger cents MAE than the synthetic set.
    """
    import soundfile as sf
    res = {}
    wavs = sorted(wav_dir.glob("*.wav"))
    for dname, fn in detectors.items():
        n_lab = n_val = gross = octv = hits = 0
        errs = []
        for w in wavs:
            audio, sr = sf.read(w, dtype="float32")
            assert sr == int(cfg.sample_rate), f"{w.name}: expected {int(cfg.sample_rate)} Hz"
            lab = np.loadtxt(w.with_suffix(".f0.csv"), delimiter=",", skiprows=1)
            clip = synth.Clip(w.stem, audio, np.zeros(1), np.zeros(1), 0, 0, {"vib_rate": 0})
            t, hz, _, v, _ = fn(clip, cfg)
            ref = np.interp(t, lab[:, 0], lab[:, 1], left=0, right=0)
            ref[np.interp(t, lab[:, 0], (lab[:, 1] > 0).astype(float)) < 0.999] = 0   # no interpolating across unvoiced
            m = ref > 0
            est_ok = m & v & (hz > 0)
            e = metrics.cents_err(hz[est_ok], ref[est_ok])
            n_lab += int(m.sum())
            n_val += int(est_ok.sum())
            hits += int((np.abs(e) <= 50).sum())
            g = np.abs(e) > 50
            gross += int(g.sum())
            octv += int((np.abs(np.abs(e) - 1200) < 50).sum())
            errs.extend(np.abs(e[~g]).tolist())
        res[dname] = {
            "files": len(wavs),
            "raw_pitch_accuracy_pct": 100 * hits / max(n_lab, 1),
            "gross_error_pct": 100 * gross / max(n_val, 1),
            "octave_error_pct": 100 * octv / max(n_val, 1),
            "voicing_recall_pct": 100 * n_val / max(n_lab, 1),
            "cents_mae_frame": float(np.mean(errs)) if errs else float("nan"),
        }
        print(f"[{dname}@{wav_dir.name}] " + ", ".join(f"{k}={x:.2f}" for k, x in res[dname].items()))
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="reports/phase0")
    ap.add_argument("--no-pyin", action="store_true")
    ap.add_argument("--wav-dir", help="dir of prepared wav + .f0.csv pairs (fetch_datasets.py output)")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    cfg = yin_ref.YinConfig()
    clips = synth.build_set()
    detectors = {"yin": run_yin} if args.no_pyin else {"yin": run_yin, "pyin": run_pyin}

    report = {"config": cfg.__dict__, "n_clips": len(clips), "detectors": {}}
    for dname, fn in detectors.items():
        rows, per_group, cpu = [], {}, []
        for c in clips:
            t, hz, hzc, v, per_hop = fn(c, cfg)
            row = metrics.score_clip(t, hz, hzc, v, c)
            row["name"] = c.name
            rows.append(row)
            per_group.setdefault(group_of(c.name), []).append(row)
            cpu.append(per_hop)
        agg = metrics.aggregate(rows)
        agg["python_ms_per_hop"] = 1000 * float(np.mean(cpu))
        # the gate metric: stable, non-vibrato notes, clean + noisy
        agg["gate_cents_mae_stable"] = agg["cents_mae_centre_stable"]
        agg["gate_pass"] = bool(agg["gate_cents_mae_stable"] < GATE_MAE)
        groups = {g: metrics.aggregate(r) for g, r in per_group.items()}
        worst = sorted(rows, key=lambda r: -(r["gross"] / max(r["n_valid"], 1)))[:5]
        report["detectors"][dname] = {
            "overall": agg,
            "by_condition": groups,
            "worst_gross_clips": [(w["name"], w["gross"], w["n_valid"]) for w in worst],
        }
        print(f"[{dname}] " + ", ".join(f"{k}={v:.2f}" for k, v in agg.items() if isinstance(v, float)))

    if args.wav_dir:
        report["real_audio"] = score_wav_dir(Path(args.wav_dir), detectors, cfg)

    (out / "report.json").write_text(json.dumps(report, indent=2, default=float))
    (out / "report.md").write_text(to_markdown(report))
    print(f"wrote {out/'report.json'} and {out/'report.md'}")


def to_markdown(rep):
    keys = [
        ("raw_pitch_accuracy_pct", "Raw pitch accuracy (±50¢) %", ""),
        ("gross_error_pct", "Gross pitch error %", "< 1"),
        ("octave_error_pct", "Octave error %", ""),
        ("voicing_recall_pct", "Voicing recall on notes %", ""),
        ("voicing_false_alarm_pct", "Voicing false alarm (silence) %", ""),
        ("cents_mae_frame_stable", "Cents MAE, per frame (raw)", ""),
        ("cents_mae_centre_stable", "Cents MAE, displayed centre, stable", "< 3 (Phase 0 gate < 5)"),
        ("cents_mae_centre_vibrato", "Cents MAE, vibrato centre", "< 5"),
        ("python_ms_per_hop", "Python ms per hop (not the C++ budget)", ""),
    ]
    dets = list(rep["detectors"])
    lines = ["# Phase 0 baseline report", "",
             f"Synthetic set: {rep['n_clips']} clips (G3–E7, sine/saw/violin-like, detune ±1–50¢, "
             "vibrato 4–8 Hz 10–80¢, pink noise 30/20/10 dB). URMP/NSynth not yet run.", "",
             "| Metric | Target | " + " | ".join(dets) + " |",
             "|---|---|" + "---|" * len(dets)]
    for k, label, tgt in keys:
        vals = [f"{rep['detectors'][d]['overall'][k]:.2f}" for d in dets]
        lines.append(f"| {label} | {tgt} | " + " | ".join(vals) + " |")
    lines.append("| **Phase 0 gate (MAE < 5¢)** |  | " + " | ".join(
        "PASS" if rep["detectors"][d]["overall"]["gate_pass"] else "FAIL" for d in dets) + " |")
    for d in dets:
        lines += ["", f"## {d} by condition", "",
                  "| Condition | RPA % | Gross % | Octave % | Centre MAE ¢ | Vib-centre MAE ¢ | FA % |",
                  "|---|---|---|---|---|---|---|"]
        for g, a in rep["detectors"][d]["by_condition"].items():
            lines.append(f"| {g} | {a['raw_pitch_accuracy_pct']:.1f} | {a['gross_error_pct']:.2f} | "
                         f"{a['octave_error_pct']:.2f} | {a['cents_mae_centre_stable']:.2f} | "
                         f"{a['cents_mae_centre_vibrato']:.2f} | {a['voicing_false_alarm_pct']:.2f} |")
        lines += ["", "Worst clips by gross error: " + ", ".join(
            f"{n} ({g}/{v})" for n, g, v in rep["detectors"][d]["worst_gross_clips"])]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    main()
