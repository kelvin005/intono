"""Phase 1 accuracy harness: score libintono (via intono-cli) on the synthetic set.

Runs the C++ core over every synthetic clip, scores it with the SAME metrics as the Phase 0
Python reference, checks frame-by-frame parity with yin_ref.py, measures onset F1 and CPU per
hop, and writes reports/phase1/report.{json,md}. Exit code 1 if a gate target is missed.

    python run_cpp.py --cli /path/to/intono-cli [--out reports/phase1] [--baseline reports/phase0/report.json]

Notes
  * intono_frame.hz is the DISPLAYED (vibrato-centre) pitch, so gross/octave/RPA are measured on
    that value against the intended pitch (f0_centre); Phase 0 measured them on the raw per-frame
    estimate against the instantaneous f0. Centre-pitch metrics are
    identical in meaning to Phase 0.
  * Regression gate (from the architecture doc): fail if any metric is worse than the Phase 0
    baseline by more than 0.5 percentage points / 0.5 cents.
"""
from __future__ import annotations

import argparse
import io
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from dataclasses import replace

import numpy as np
import soundfile as sf

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "ref"))
import metrics  # noqa: E402
import synth  # noqa: E402
import stream_ref  # noqa: E402
import yin_ref  # noqa: E402

TARGETS = {  # architecture doc: Accuracy and performance targets
    "gross_error_pct": ("<", 1.0),
    "cents_mae_centre_stable": ("<", 3.0),
    "cents_mae_centre_vibrato": ("<", 5.0),
    "us_per_hop": ("<", 1000.0),  # "CPU per hop under 1 ms on a laptop" (Phase 1 gate)
}
NOTE_TARGETS = {  # proposed with ADR 0003 before the first measurement; whole phrase set (dev + held-out seeds)
    "note_precision": (">=", 0.98),
    "note_recall": (">=", 0.98),
    "note_cents_mae": ("<", 3.0),
}
ONSET_WINDOW = (-0.03, 0.12)
PHRASE_SEEDS = {"dev": 21, "heldout_77": 77, "heldout_123": 123, "heldout_2024": 2024}  # dev drove the fixes; the rest did not


def run_cli(cli, wav, *extra):
    r = subprocess.run([cli, str(wav), *extra], capture_output=True, text=True, check=True)
    return r


def parse_frames(text):
    a = np.loadtxt(io.StringIO(text), delimiter=",", skiprows=1)
    return {"t": a[:, 0], "hz": a[:, 1], "conf": a[:, 2], "midi": a[:, 3], "cents": a[:, 4],
            "vib_rate": a[:, 5], "vib_width": a[:, 6], "voiced": a[:, 7] > 0, "onset": a[:, 8] > 0}


def parse_notes(text):
    a = np.loadtxt(io.StringIO(text), delimiter=",", skiprows=1, ndmin=2)
    return [stream_ref.Note(r[0], r[1], int(r[2]), r[3], r[4], r[5], r[6], r[7], int(r[8])) for r in a]


def note_section(cli, td):
    """Note-level scoring of libintono on labelled phrases + parity of notes and onset flags with the Python mirror."""
    per_set, all_rows = {}, []
    par = {"phrases": 0, "note_count_mismatch": 0, "note_value_mismatch": 0, "onset_flag_mismatch_frames": 0,
           "max_mean_cents_diff": 0.0, "max_time_diff_s": 0.0}
    for label, seed in PHRASE_SEEDS.items():
        rows = []
        for ph in synth.build_phrase_set(seed):
            wav = Path(td) / f"{ph.name}.wav"
            sf.write(wav, ph.audio, synth.SR, subtype="FLOAT")
            notes = parse_notes(run_cli(cli, wav, "--notes", "1").stdout)
            rows.append(metrics.score_notes(ph.notes, notes))
            if label == "dev":                               # the Python mirror is slow: parity on the dev set only
                _, onset_py, notes_py = stream_ref.run_stream(np.concatenate([ph.audio, np.zeros(9600, np.float32)]))
                par["phrases"] += 1
                if len(notes) != len(notes_py):
                    par["note_count_mismatch"] += 1
                else:
                    for q, e in zip(notes, notes_py):
                        par["max_mean_cents_diff"] = max(par["max_mean_cents_diff"], abs(q.mean_cents - e.mean_cents), abs(q.std_cents - e.std_cents))
                        par["max_time_diff_s"] = max(par["max_time_diff_s"], abs(q.t_start - e.t_start), abs(q.t_end - e.t_end))
                        if q.midi_note != e.midi_note or q.frames != e.frames:
                            par["note_value_mismatch"] += 1
                fr = parse_frames(run_cli(cli, wav).stdout)
                n = min(len(fr["onset"]), len(onset_py))
                par["onset_flag_mismatch_frames"] += int(np.sum(fr["onset"][:n] != onset_py[:n]))
        per_set[label] = metrics.aggregate_notes(rows)
        all_rows += rows
    overall = metrics.aggregate_notes(all_rows)
    gates = {}
    for k, (op, lim) in NOTE_TARGETS.items():
        ok = overall[k] >= lim if op == ">=" else overall[k] < lim
        gates[k] = {"value": overall[k], "target": f"{op} {lim}", "pass": bool(ok)}
    return {"overall": overall, "by_set": per_set, "gates": gates, "parity_vs_python_reference": par}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cli", required=True)
    ap.add_argument("--out", default=str(HERE / "reports/phase1"))
    ap.add_argument("--baseline", default=str(HERE / "reports/phase0/report.json"))
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    cfg = yin_ref.YinConfig()
    clips = synth.build_set()
    rows, per_group = [], {}
    diffs, vmis, nfr = [], 0, 0
    tp = fp = fn = 0
    bench_wav = None
    with tempfile.TemporaryDirectory() as td:
        for c in clips:
            wav = Path(td) / f"{c.name}.wav"
            sf.write(wav, c.audio, synth.SR, subtype="FLOAT")
            f = parse_frames(run_cli(args.cli, wav).stdout)
            # the displayed pitch is a vibrato centre, so it is scored against the intended pitch,
            # not the instantaneous f0 that swings +-40 c around it
            row = metrics.score_clip(f["t"], f["hz"], f["hz"], f["voiced"], replace(c, f0=c.f0_centre))
            row["name"] = c.name
            rows.append(row)
            per_group.setdefault(c.name.split("_", 1)[1], []).append(row)

            ref = yin_ref.analyse(c.audio, cfg)           # parity with the Python reference
            n = min(len(f["t"]), len(ref.t))
            both = (f["hz"][:n] > 0) & (ref.hz_centre[:n] > 0)
            diffs.extend(np.abs(1200 * np.log2(f["hz"][:n][both] / ref.hz_centre[:n][both])).tolist())
            vmis += int(np.sum(f["voiced"][:n] != ref.voiced[:n]))
            nfr += n

            on = f["t"][f["onset"]]                       # onset F1 against the known note start
            hit = on[(on >= c.note_on + ONSET_WINDOW[0]) & (on <= c.note_on + ONSET_WINDOW[1])]
            if len(hit):
                tp += 1
                fp += len(on) - 1
            else:
                fn += 1
                fp += len(on)
            if c.name == "m70_violin":
                bench_wav = Path(td) / "bench.wav"
                sf.write(bench_wav, np.tile(c.audio, 20), synth.SR, subtype="FLOAT")
        bench = run_cli(args.cli, bench_wav, "--bench", "20").stderr
        notes_rep = note_section(args.cli, td)
    us_per_hop = float(bench.split("bench:")[1].split("us/hop")[0])

    agg = metrics.aggregate(rows)
    agg["us_per_hop"] = us_per_hop
    prec, rec = tp / max(tp + fp, 1), tp / max(tp + fn, 1)
    agg["onset_precision"], agg["onset_recall"] = prec, rec
    agg["onset_f1"] = 2 * prec * rec / max(prec + rec, 1e-9)
    groups = {g: metrics.aggregate(r) for g, r in per_group.items()}
    parity = {"frames": nfr, "voiced_mismatch_frames": vmis,
              "centre_diff_cents_median": float(np.median(diffs)), "centre_diff_cents_p99": float(np.percentile(diffs, 99)),
              "centre_diff_cents_max": float(np.max(diffs))}

    gates = {}
    for k, (op, lim) in TARGETS.items():
        gates[k] = {"value": agg[k], "target": f"{op} {lim}", "pass": bool(agg[k] < lim)}
    regress = {}
    base_path = Path(args.baseline)
    if base_path.exists():
        base = json.loads(base_path.read_text())["detectors"]["yin"]["overall"]
        for k, tol in [("gross_error_pct", 0.5), ("octave_error_pct", 0.5), ("cents_mae_centre_stable", 0.5), ("cents_mae_centre_vibrato", 0.5),
                       ("voicing_false_alarm_pct", 0.5)]:
            regress[k] = {"phase0": base[k], "phase1": agg[k], "pass": bool(agg[k] <= base[k] + tol)}
    report = {"overall": agg, "gates": gates, "regression_vs_phase0": regress, "parity_vs_python_reference": parity, "by_condition": groups, "notes": notes_rep}
    (out / "report.json").write_text(json.dumps(report, indent=2, default=float))
    (out / "report.md").write_text(to_md(report, len(clips)))
    print((out / "report.md").read_text())
    ok = (all(g["pass"] for g in gates.values()) and all(r["pass"] for r in regress.values())
          and all(g["pass"] for g in notes_rep["gates"].values()))
    sys.exit(0 if ok else 1)


def to_md(rep, n):
    a, p = rep["overall"], rep["parity_vs_python_reference"]
    L = ["# Phase 1 accuracy report (libintono, C++)", "",
         f"Synthetic set: {n} clips, scored through `intono-cli` with the Phase 0 metrics. Real recordings (URMP, NSynth) not yet run.", "",
         "## Gate targets", "", "| Metric | Target | Result | |", "|---|---|---|---|"]
    for k, g in rep["gates"].items():
        L.append(f"| {k} | {g['target']} | {g['value']:.3f} | {'PASS' if g['pass'] else '**FAIL**'} |")
    L += ["", "## Regression against Phase 0 (allowed: +0.5 pp / +0.5 c)", "", "| Metric | Phase 0 (Python) | Phase 1 (C++) | |", "|---|---|---|---|"]
    for k, r in rep["regression_vs_phase0"].items():
        L.append(f"| {k} | {r['phase0']:.3f} | {r['phase1']:.3f} | {'PASS' if r['pass'] else '**FAIL**'} |")
    L += ["", "## Other metrics", "",
          f"- Raw pitch accuracy (±50¢, displayed pitch): {a['raw_pitch_accuracy_pct']:.2f}%",
          f"- Octave error: {a['octave_error_pct']:.3f}%   Voicing recall: {a['voicing_recall_pct']:.2f}%   False alarm in silence: {a['voicing_false_alarm_pct']:.3f}%",
          f"- Cents MAE per frame (displayed, stable): {a['cents_mae_frame_stable']:.3f}   p95: {a['cents_p95_frame_stable']:.3f}",
          f"- Onset on note start: precision {a['onset_precision']:.3f}, recall {a['onset_recall']:.3f}, F1 {a['onset_f1']:.3f}",
          f"- CPU: {a['us_per_hop']:.1f} µs per 5.33 ms hop ({100*a['us_per_hop']/5333.3:.2f}% of one core, this machine)",
          "", "## Parity with the Python reference (frame by frame)", "",
          f"- {p['frames']} frames compared, voiced mismatches: {p['voiced_mismatch_frames']}",
          f"- Displayed pitch difference: median {p['centre_diff_cents_median']:.5f} c, p99 {p['centre_diff_cents_p99']:.5f} c, max {p['centre_diff_cents_max']:.5f} c",
          "", *notes_md(rep["notes"]),
          "", "## By condition", "", "| Condition | Gross % | Centre MAE ¢ | Vib-centre MAE ¢ | FA % |", "|---|---|---|---|---|"]
    for g, x in rep["by_condition"].items():
        L.append(f"| {g} | {x['gross_error_pct']:.2f} | {x['cents_mae_centre_stable']:.2f} | {x['cents_mae_centre_vibrato']:.2f} | {x['voicing_false_alarm_pct']:.2f} |")
    return "\n".join(L) + "\n"


def notes_md(nr):
    o, p = nr["overall"], nr["parity_vs_python_reference"]
    L = ["## Note level (ADR 0003): labelled synthetic phrases, 8 notes each, separated and legato, ±40 c detuning, 40% vibrato, clean / 20 dB / 10 dB SNR", "",
         "| Gate | Target | Result | |", "|---|---|---|---|"]
    for k, g in nr["gates"].items():
        L.append(f"| {k} | {g['target']} | {g['value']:.3f} | {'PASS' if g['pass'] else '**FAIL**'} |")
    L += ["", f"- {o['note_count_true']} true notes, {o['note_count_est']} reported; notes with the right ET number but start >50 ms off count as misses; "
          f"wrong-number notes at the right time: {o['note_wrong_midi']}",
          f"- Cents error of the whole-note mean vs the intended detuning: steady notes MAE {o['note_cents_mae']:.3f}, p95 {o['note_cents_p95']:.3f}; "
          f"vibrato notes MAE {o['note_cents_mae_vibrato']:.3f} (whole-note mean of the raw pitch, partial cycles included)",
          f"- Timing: start MAE {o['note_onset_mae_ms']:.1f} ms, end MAE {o['note_offset_mae_ms']:.1f} ms",
          "", "| Phrase set | Precision | Recall | Wrong # | Steady MAE ¢ | Vib MAE ¢ |", "|---|---|---|---|---|---|"]
    for k, a in nr["by_set"].items():
        L.append(f"| {k} | {a['note_precision']:.3f} | {a['note_recall']:.3f} | {a['note_wrong_midi']} | {a['note_cents_mae']:.3f} | {a['note_cents_mae_vibrato']:.3f} |")
    L += ["", f"Parity with the Python mirror on the dev set ({p['phrases']} phrases): note count mismatches {p['note_count_mismatch']}, "
          f"note value mismatches {p['note_value_mismatch']}, onset-flag mismatch frames {p['onset_flag_mismatch_frames']}, "
          f"max mean/std difference {p['max_mean_cents_diff']:.4f} c, max time difference {p['max_time_diff_s']:.5f} s"]
    return L


if __name__ == "__main__":
    main()
