#!/usr/bin/env python3
"""ADR 0006 runbook step 4: feature selection, leave-one-group-out, hysteresis and thresholds. DEV DATA ONLY.

  fit.py --feats dev_feats.npz [--feats more.npz ...] --out model.json [--max-rows 30000] [--report report.md]

Selection rule (fixed in ADR 0006): forward selection from the empty model over F1..F7, at most 4 features; a feature is added if it
lowers the pooled leave-one-group-out balanced log-loss by >= 2 % (relative). Model: logistic regression, L2 with C = 1.0 (sklearn),
on the FIXED-scaled features (features.py). Groups: speaker (speech) / instrument (violin). Labels: violin = 1; speech and noise = 0;
overlap and decay frames are excluded.
Then N_on in {2,3,4,6}, N_off in {3,6,10}: theta_lo = the lowest value with violin frames lost <= 0.2 % (half the 0.5 % gate),
theta_hi = the lowest value with speech notes (proxy: runs of >= 10 accepted hops whose median score >= theta_lo) <= 0.25 per minute
in EVERY speech group (half the 0.5 gate). Among feasible (N_on, N_off) the one with the fewest speech frames voiced wins; ties go to the
smaller N_on, then the smaller N_off. (This tie rule was written with the tool, before any data; it goes in the pre-registration.)
If nothing is feasible, B has failed on development: the tool says so and stops (trigger for option C).
The proxy notes are NOT the gate: G1 is measured with the engine (eval_gates.py). Baselines (A and a plain confidence threshold) are
fitted with the same rule and reported side by side.
"""
import argparse
import json

import numpy as np
from sklearn.linear_model import LogisticRegression

from features import FEATURES

N_ON, N_OFF = [2, 3, 4, 6], [3, 6, 10]
MIN_NOTE_HOPS = 10
HOP_S = 256 / 48000.0
LOSS_VIOLIN_MAX, SPEECH_PER_MIN_MAX = 0.002, 0.25


def load(paths):
    parts = [np.load(p, allow_pickle=True) for p in paths]
    d = {k: np.concatenate([p[k] for p in parts]) for k in parts[0].files if k != "feature_names"}
    return d


def design(d, names):
    X = np.stack([d[n] for n in names], axis=1).astype(float)
    return np.nan_to_num(X, nan=0.5)      # undefined (no f0, too few harmonics) -> mid-range; the same rule goes in C++


def balanced_logloss(y, p):
    p = np.clip(p, 1e-6, 1 - 1e-6)
    ll = -(y * np.log(p) + (1 - y) * np.log(1 - p))
    return 0.5 * (ll[y == 1].mean() + ll[y == 0].mean())


def logo_loss(X, y, groups, max_rows, seed=0):
    rng = np.random.default_rng(seed)
    idx = np.arange(len(y))
    if len(idx) > max_rows:                          # selection uses a fixed random subsample; the final fit uses all rows
        idx = np.sort(rng.choice(idx, max_rows, replace=False))
    X, y, g = X[idx], y[idx], groups[idx]
    pred = np.zeros(len(y))
    for gv in np.unique(g):
        te = g == gv
        tr = ~te
        if len(np.unique(y[tr])) < 2:
            pred[te] = y[tr].mean() if tr.any() else 0.5
            continue
        m = LogisticRegression(C=1.0, max_iter=300).fit(X[tr], y[tr])
        pred[te] = m.predict_proba(X[te])[:, 1]
    return balanced_logloss(y, pred), pred, idx


def forward_select(d, mask, max_rows):
    y = (d["label"][mask] == 1).astype(int)
    groups = d["group"][mask]
    chosen, best, log = [], None, []
    for _ in range(4):
        cands = []
        for f in FEATURES:
            if f in chosen:
                continue
            X = design({k: v[mask] for k, v in d.items() if k in FEATURES}, chosen + [f])
            cands.append((logo_loss(X, y, groups, max_rows)[0], f))
        loss, f = min(cands)
        gain = None if best is None else (best - loss) / best
        log.append(dict(candidates={c[1]: round(c[0], 5) for c in cands}, best=f, loss=round(loss, 5), rel_gain=None if gain is None else round(gain, 4)))
        if best is not None and gain < 0.02:
            break
        chosen.append(f)
        best = loss
    return chosen, log


def simulate(score, base_voiced, theta_hi, theta_lo, n_on, n_off):
    """Hysteresis over one clip: accepted state per hop. Hops the engine calls unvoiced have score -inf."""
    s = np.where(base_voiced, score, -np.inf)
    out = np.zeros(len(s), bool)
    on, up, down = False, 0, 0
    for i, v in enumerate(s):
        if not on:
            up = up + 1 if v >= theta_hi else 0
            if up >= n_on:
                on, down = True, 0
        else:
            down = down + 1 if v < theta_lo else 0
            if down >= n_off:
                on, up = False, 0
        out[i] = on
    return out


def runs(mask):
    d = np.diff(np.concatenate([[0], mask.astype(int), [0]]))
    return list(zip(np.where(d == 1)[0], np.where(d == -1)[0]))


def evaluate(d, score, clips, theta_hi, theta_lo, n_on, n_off):
    """violin frames lost (fraction of base-voiced violin hops, run starts excluded) and speech stats per speech group."""
    lost = tot = 0
    sp_notes, sp_min, sp_voiced, sp_hops = {}, {}, {}, {}
    for c in clips:
        m = d["clip"] == c
        voiced = d["voiced"][m].astype(bool)
        lab = d["label"][m]
        sc = score[m]
        acc = simulate(sc, voiced, theta_hi, theta_lo, n_on, n_off)
        # violin frames lost: base-voiced violin hops that are not accepted, excluding the first n_on hops of each base-voiced run
        for a, b in runs(voiced):
            hops = np.arange(a, b)
            hops = hops[min(len(hops), n_on):]
            sel = hops[lab[hops] == 1]
            lost += int((~acc[sel]).sum())
            tot += len(sel)
        g = d["speech_group"][m][0]
        sp_hops_c = (lab == 0).sum()
        if g and sp_hops_c:
            sp_min[g] = sp_min.get(g, 0.0) + sp_hops_c * HOP_S / 60.0
            sp_voiced[g] = sp_voiced.get(g, 0) + int((acc & (lab == 0)).sum())
            sp_hops[g] = sp_hops.get(g, 0) + int(sp_hops_c)
            n = 0
            for a, b in runs(acc):
                if b - a >= MIN_NOTE_HOPS and np.median(sc[a:b]) >= theta_lo and (lab[a:b] == 0).mean() > 0.5:
                    n += 1
            sp_notes[g] = sp_notes.get(g, 0) + n
    return dict(violin_lost=lost / max(tot, 1), violin_hops=tot,
                speech_notes_per_min={g: sp_notes.get(g, 0) / max(sp_min[g], 1e-9) for g in sp_min},
                speech_frames_voiced={g: sp_voiced[g] / max(sp_hops[g], 1) for g in sp_hops}, speech_minutes=sp_min)


def choose_operating_point(d, score):
    clips = sorted(set(d["clip"]))
    grid = sorted(set(np.round(np.quantile(score[np.isfinite(score)], np.linspace(0.01, 0.99, 50)), 4)))
    best = None
    for n_on in N_ON:
        for n_off in N_OFF:
            lo = next((t for t in grid if evaluate(d, score, clips, t, t, n_on, n_off)["violin_lost"] <= LOSS_VIOLIN_MAX), None)
            if lo is None:
                continue
            hi = next((t for t in grid if t >= lo and max(evaluate(d, score, clips, t, lo, n_on, n_off)["speech_notes_per_min"].values() or [0]) <= SPEECH_PER_MIN_MAX), None)
            if hi is None:
                continue
            ev = evaluate(d, score, clips, hi, lo, n_on, n_off)
            if ev["violin_lost"] > LOSS_VIOLIN_MAX:
                continue
            key = (max(ev["speech_frames_voiced"].values() or [0]), n_on, n_off)
            if best is None or key < best[0]:
                best = (key, dict(N_on=n_on, N_off=n_off, theta_lo=float(lo), theta_hi=float(hi), eval=ev))
    return None if best is None else best[1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--feats", nargs="+", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-rows", type=int, default=30000)
    ap.add_argument("--report", default=None)
    a = ap.parse_args()
    d = load(a.feats)
    use = d["voiced"].astype(bool) & (d["label"] >= 0)
    n_g = len(set(d["group"][use]))
    print(f"{use.sum()} labelled voiced hops, {n_g} groups")
    chosen, log = forward_select(d, use, a.max_rows)
    print("selected:", chosen)
    y = (d["label"][use] == 1).astype(int)
    X = design({k: v[use] for k, v in d.items() if k in FEATURES}, chosen)
    final = LogisticRegression(C=1.0, max_iter=1000).fit(X, y)
    full_X = design(d, chosen)
    score = final.predict_proba(full_X)[:, 1]
    op = choose_operating_point(d, score)
    res = dict(features=chosen, weights=[float(w) for w in final.coef_[0]], bias=float(final.intercept_[0]), selection_log=log,
               operating_point=op, n_free_numbers=(len(chosen) + 1 + 5 if op else None))
    # baseline: confidence threshold alone (same rule, F1 only)
    if "F1_conf" in FEATURES:
        s1 = d["F1_conf"].astype(float)
        res["baseline_confidence_only"] = choose_operating_point(d, s1)
    json.dump(res, open(a.out, "w"), indent=1, default=float)
    if op is None:
        print("NO FEASIBLE OPERATING POINT: option B fails on development data (ADR 0006 trigger for option C). Nothing sealed is touched.")
    else:
        e = op["eval"]
        print(f"N_on {op['N_on']} N_off {op['N_off']} theta_lo {op['theta_lo']} theta_hi {op['theta_hi']}")
        print(f"violin lost {e['violin_lost']:.4%}   speech notes/min {e['speech_notes_per_min']}   speech frames voiced {e['speech_frames_voiced']}")
    if a.report:
        with open(a.report, "w") as f:
            f.write("# ADR 0006 fit report (dev data)\n\n```\n" + json.dumps(res, indent=1, default=float) + "\n```\n")


if __name__ == "__main__":
    main()
