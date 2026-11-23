#!/usr/bin/env python3
"""ADR 0006 gates G1-G6 (generated mixtures) and G9 (real clips), measured against the FROZEN engine.

  eval_gates.py mix  --mix-dir DIR --cli-base FROZEN [--cli-new CANDIDATE] [--out report.md] [--sealed NAME]
  eval_gates.py real --annot annotations.json --cli-base FROZEN [--cli-new CANDIDATE] [--out report.md]

Without --cli-new it writes the BASELINE (runbook step 2: the problem and the bases of G3/G4/G6). With --cli-new it also compares.
Definitions (ADR 0006): a speech note is an engine note whose middle falls in a speech-only interval (truth speech minus any violin note
+-50 ms); G1 = such notes per minute of speech-only audio, per speech group; G2 = fraction of hops with voiced=1 in those intervals; G3 =
truth notes found by the new engine / truth notes found by the base (same MIDI number, start within 80 ms of the truth onset);
G4 = base-voiced violin hops the new engine calls unvoiced (first N hops after a pause are G5); G5 = delay of the first voiced hop
after each truth onset, new minus base; G6 = G3 on layouts c and d, by violin-over-speech level.
A sealed run (--sealed NAME) needs a registered name, the registered seed hash and the frozen binary, and runs once.
real: annotations.json = {"set": "dev|sealed", "clips": [{"wav": path, "speech": [[s,e],...], "playing": [[s,e],...]}]}; G9 carries weight only
if the set has >= 10 min of playing and >= 4 min of speech.
"""
import argparse
import datetime
import hashlib
import os
import sys
from collections import defaultdict

import numpy as np

from common import FROZEN_CLI, ROOT, read_json, run_cli, sha256_file

LOG = os.path.join(ROOT, "tools", "voice", "reports", "sealed_runs.log")
SEALED = {}    # name -> dict(seeds=[...], sha="sha256 of 'seed,seed,...'", spent=None); registered before the run, like the earlier sealed sets
GATES = dict(G1=0.5, G2=0.05, G3=0.995, G4=0.005, G5=0.030, G6=0.98)
MATCH_S = 0.08


def speech_only(truth):
    out = []
    for s in truth["speech"]:
        segs = [(s["start"], s["end"])]
        for n in truth["notes"]:
            nxt = []
            for a, b in segs:
                lo, hi = n["onset"] - 0.05, n["offset"] + 0.05
                if hi <= a or lo >= b:
                    nxt.append((a, b))
                else:
                    if lo > a:
                        nxt.append((a, lo))
                    if hi < b:
                        nxt.append((hi, b))
            segs = nxt
        out += [(a, b, s["group"]) for a, b in segs if b - a > 0.05]
    return out


def found(truth_notes, notes):
    """set of indices of truth notes matched by an engine note (each engine note used once)."""
    used, hit = set(), set()
    for i, n in enumerate(truth_notes):
        best = None
        for j, e in enumerate(notes):
            if j in used or int(e[2]) != n["midi"]:
                continue
            dt = abs(e[0] - n["onset"])
            if dt <= MATCH_S and (best is None or dt < best[0]):
                best = (dt, j)
        if best:
            used.add(best[1])
            hit.add(i)
    return hit


def bucket(n):
    b = ["all"]
    b.append("soft(v<=50)" if n["velocity"] <= 50 else "loud(v>=100)" if n["velocity"] >= 100 else "mid")
    if n["midi"] < 59:
        b.append("low(G3-B3)")
    if n["midi"] > 88:
        b.append("high(>E6)")
    if n["dur"] <= 0.101:
        b.append("short(<=100ms)")
    if "fast_decay" in n.get("quality", []):
        b.append("pizzicato-like")
    return b


def onset_delays(frames, onsets):
    out = []
    for o in onsets:
        idx = np.where((frames[:, 0] >= o) & (frames[:, 7] > 0.5))[0]
        out.append(frames[idx[0], 0] - o if len(idx) and frames[idx[0], 0] - o < 0.5 else np.nan)
    return np.array(out)


def run_set(mix_dir, cli):
    res = {}
    for f in sorted(os.listdir(mix_dir)):
        if f.endswith(".wav"):
            w = os.path.join(mix_dir, f)
            res[f] = dict(notes=run_cli(cli, w, notes=True), frames=run_cli(cli, w))
    return res


def mix_metrics(mix_dir, base, new):
    truth = {f: read_json(os.path.join(mix_dir, f[:-4] + ".json")) for f in base}
    m = dict(speech_min=defaultdict(float), speech_notes=defaultdict(lambda: defaultdict(int)), speech_hops=defaultdict(int),
             speech_voiced=defaultdict(lambda: defaultdict(int)), g3=defaultdict(lambda: [0, 0, 0]), g6=defaultdict(lambda: [0, 0]), lost=[0, 0],
             delays=[], noise_notes=defaultdict(int), noise_min=0.0)
    for f, T in truth.items():
        ivs = speech_only(T)
        for tag, R in (("base", base), ("new", new)):
            if R is None:
                continue
            fr, nt = R[f]["frames"], R[f]["notes"]
            mid = (nt[:, 0] + nt[:, 1]) / 2 if len(nt) else np.zeros(0)
            for a, b, g in ivs:
                if tag == "base":
                    m["speech_min"][g] += (b - a) / 60.0
                    m["speech_hops"][g] += int(((fr[:, 0] >= a) & (fr[:, 0] <= b)).sum())
                m["speech_notes"][tag][g] += int(((mid >= a) & (mid <= b)).sum())
                m["speech_voiced"][tag][g] += int((((fr[:, 0] >= a) & (fr[:, 0] <= b)) & (fr[:, 7] > 0.5)).sum())
            if T["layout"] == "n":
                m["noise_notes"][tag] += len(nt)
        if T["notes"] and new is not None:
            fb, fn = found(T["notes"], base[f]["notes"]), found(T["notes"], new[f]["notes"])
            for i, n in enumerate(T["notes"]):
                if i in fb:
                    for b in bucket(n) + ["cond:" + T["cond"]]:
                        m["g3"][b][0] += 1
                        m["g3"][b][1] += int(i in fn)
                    if T["layout"] in ("c", "d"):
                        key = f"layout {T['layout']}" + (f", violin over speech {T['violin_over_speech_db']:+d} dB" if T["layout"] == "d" else "")
                        m["g6"][key][0] += 1
                        m["g6"][key][1] += int(i in fn)
            if T["layout"] == "v":
                fb_, fn_ = base[f]["frames"], new[f]["frames"]
                for n in T["notes"]:
                    sel = (fb_[:, 0] >= n["onset"]) & (fb_[:, 0] <= n["offset"]) & (fb_[:, 7] > 0.5)
                    first = fb_[sel][:1, 0]
                    cut = first[0] if len(first) else None
                    if cut is None:
                        continue
                    # hops after the first voiced hop; the onset hops go to G5
                    later = (fb_[:, 0] > cut) & sel
                    m["lost"][1] += int(later.sum())
                    m["lost"][0] += int((later & (fn_[:, 7] < 0.5)).sum())
                db, dn = onset_delays(fb_, [n["onset"] for n in T["notes"]]), onset_delays(fn_, [n["onset"] for n in T["notes"]])
                m["delays"] += list(dn - db)
    return m


def report(m, has_new, label):
    L = [f"# ADR 0006 gates: {label}", "", f"base = frozen engine; new = {'candidate' if has_new else '(none: baseline only)'}", ""]
    L += ["## G1, G2: speech notes per minute and speech frames voiced (speech-only intervals), per speech group", "",
          "| group | speech min | base notes/min | new notes/min | G1 | base frames voiced | new frames voiced | G2 |", "|---|---|---|---|---|---|---|---|"]
    ok = True
    for g in sorted(m["speech_min"]):
        mn = max(m["speech_min"][g], 1e-9)
        bn, nn = m["speech_notes"]["base"][g] / mn, m["speech_notes"]["new"][g] / mn if has_new else None
        bv, nv = m["speech_voiced"]["base"][g] / max(m["speech_hops"][g], 1), m["speech_voiced"]["new"][g] / max(m["speech_hops"][g], 1) if has_new else None
        g1 = "-" if nn is None else ("PASS" if nn <= GATES["G1"] else "FAIL")
        g2 = "-" if nv is None else ("PASS" if nv <= GATES["G2"] else "FAIL")
        ok &= g1 != "FAIL" and g2 != "FAIL"
        L.append(f"| {g} | {mn:.2f} | {bn:.2f} | {'-' if nn is None else f'{nn:.2f}'} | {g1} (<= 0.5) | {bv:.1%} | {'-' if nv is None else f'{nv:.1%}'} | {g2} (<= 5 %) |")
    if has_new:
        L += ["", "## G3: violin note recall relative to the base (>= 0.995 overall and in every bucket)", "", "| bucket | base-found notes | kept by new | recall | |", "|---|---|---|---|---|"]
        for b in sorted(m["g3"]):
            n, k, _ = m["g3"][b]
            r = k / max(n, 1)
            st = "PASS" if r >= GATES["G3"] else "FAIL"
            ok &= st == "PASS" or n < 20
            L.append(f"| {b} | {n} | {k} | {r:.4f} | {st}{' (n<20: not weighed)' if n < 20 else ''} |")
        lost, tot = m["lost"]
        L += ["", f"## G4: violin frames switched off: {lost} of {tot} = {lost / max(tot, 1):.3%} (<= 0.5 %): {'PASS' if lost / max(tot, 1) <= GATES['G4'] else 'FAIL'}"]
        ok &= lost / max(tot, 1) <= GATES["G4"]
        d = np.array(m["delays"], float)
        d = d[~np.isnan(d)]
        if len(d):
            L += [f"", f"## G5: added acceptance delay at onsets: max {d.max() * 1000:.1f} ms, p95 {np.percentile(d, 95) * 1000:.1f} ms (<= 30 ms): {'PASS' if d.max() <= GATES['G5'] else 'FAIL'}"]
            ok &= d.max() <= GATES["G5"]
        L += ["", "## G6: overlap, recall relative to the base (>= 0.98 at violin-over-speech +6 dB and above; 0 and -6 dB reported only)", "", "| case | base-found | kept | recall |", "|---|---|---|---|"]
        for k in sorted(m["g6"]):
            n, kept = m["g6"][k]
            L.append(f"| {k} | {n} | {kept} | {kept / max(n, 1):.4f} |")
            if k.startswith("layout d") and any(f"{s:+d} dB" in k for s in (6, 10, 20)):
                ok &= kept / max(n, 1) >= GATES["G6"]
        L += ["", f"Noise-only clips: notes base {m['noise_notes']['base']}, new {m['noise_notes']['new']}"]
        L += ["", f"**All gates measured on this set: {'PASS' if ok else 'FAIL'}** (G7, G8, G10 are measured elsewhere)"]
    return "\n".join(L) + "\n"


def real_metrics(annot, cli_base, cli_new):
    A = read_json(annot)
    play_min = sum(e - s for c in A["clips"] for s, e in c["playing"]) / 60.0
    sp_min = sum(e - s for c in A["clips"] for s, e in c["speech"]) / 60.0
    rows = []
    for c in A["clips"]:
        r = {}
        for tag, cli in (("base", cli_base), ("new", cli_new)):
            if not cli:
                continue
            nt, fr = run_cli(cli, c["wav"], notes=True), run_cli(cli, c["wav"])
            mid = (nt[:, 0] + nt[:, 1]) / 2 if len(nt) else np.zeros(0)
            in_sp = np.zeros(len(mid), bool)
            for s, e in c["speech"]:
                in_sp |= (mid >= s) & (mid <= e)
            in_pl = np.zeros(len(mid), bool)
            for s, e in c["playing"]:
                in_pl |= (mid >= s) & (mid <= e)
            r[tag] = dict(speech_notes=int((in_sp & ~in_pl).sum()), playing_notes=nt[in_pl] if len(nt) else nt)
        rows.append((c["wav"], sum(e - s for s, e in c["speech"]) / 60.0, r))
    return A.get("set", "?"), play_min, sp_min, rows


def real_report(setname, play_min, sp_min, rows, has_new):
    weight = play_min >= 10 and sp_min >= 4
    L = [f"# ADR 0006 G9: real clips, set '{setname}'", "", f"playing {play_min:.1f} min, speech {sp_min:.1f} min; G9 carries weight: **{'yes' if weight else 'NO (set below 10 min playing and 4 min speech: reported only)'}**", "",
         "| clip | speech min | base speech notes | new speech notes | base playing notes | new playing notes kept |", "|---|---|---|---|---|---|"]
    tb = tn = lost = tot = 0
    for wav, smin, r in rows:
        bn = r["base"]["speech_notes"]
        nn = r["new"]["speech_notes"] if "new" in r else None
        bp = r["base"]["playing_notes"]
        kept = None
        if "new" in r:
            npn = r["new"]["playing_notes"]
            kept = sum(any(int(e[2]) == int(b[2]) and abs(e[0] - b[0]) <= MATCH_S for e in npn) for b in bp)
            lost += len(bp) - kept
            tot += len(bp)
            tn += nn
        tb += bn
        L.append(f"| {os.path.basename(wav)} | {smin:.2f} | {bn} | {'-' if nn is None else nn} | {len(bp)} | {'-' if kept is None else kept} |")
    if has_new:
        rate = tn / max(sp_min, 1e-9)
        L += ["", f"speech notes {tn} in {sp_min:.2f} min = {rate:.2f} per minute (<= 0.5): {'PASS' if rate <= 0.5 else 'FAIL'}; playing notes lost {lost} of {tot} = {lost / max(tot, 1):.2%} (<= 0.5 %): {'PASS' if lost / max(tot, 1) <= 0.005 else 'FAIL'}"]
    else:
        L += ["", f"baseline: {tb} speech notes in {sp_min:.2f} min = {tb / max(sp_min, 1e-9):.1f} per minute"]
    return "\n".join(L) + "\n"


def check_sealed(name, cli):
    if name not in SEALED:
        sys.exit(f"sealed set '{name}' is not registered in eval_gates.py SEALED")
    cfg = SEALED[name]
    if cfg.get("spent"):
        sys.exit(f"sealed set '{name}' is spent ({cfg['spent']})")
    if hashlib.sha256(",".join(map(str, cfg["seeds"])).encode()).hexdigest() != cfg["sha"]:
        sys.exit("seed list does not match its registered hash")
    if os.path.exists(LOG) and any(f" set={name} " in l for l in open(LOG)):
        sys.exit(f"sealed set '{name}' has already been run; a sealed set is never reused")
    if cli == FROZEN_CLI:
        sys.exit("a sealed run needs the candidate binary as --cli-new; the frozen binary is only the base")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["mix", "real"])
    ap.add_argument("--mix-dir")
    ap.add_argument("--annot")
    ap.add_argument("--cli-base", default=FROZEN_CLI)
    ap.add_argument("--cli-new")
    ap.add_argument("--out")
    ap.add_argument("--sealed")
    a = ap.parse_args()
    if a.sealed:
        if not a.cli_new:
            sys.exit("--sealed needs --cli-new")
        check_sealed(a.sealed, a.cli_new)
    if a.mode == "mix":
        base = run_set(a.mix_dir, a.cli_base)
        new = run_set(a.mix_dir, a.cli_new) if a.cli_new else None
        txt = report(mix_metrics(a.mix_dir, base, new), new is not None, f"{os.path.basename(os.path.normpath(a.mix_dir))}, base {a.cli_base} sha {sha256_file(a.cli_base)[:12]}")
    else:
        setname, pm, sm, rows = real_metrics(a.annot, a.cli_base, a.cli_new)
        txt = real_report(setname, pm, sm, rows, bool(a.cli_new))
    print(txt)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w").write(txt)
    if a.sealed:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        open(LOG, "a").write(f"{datetime.datetime.now().isoformat(timespec='seconds')} set={a.sealed} new={a.cli_new} sha={sha256_file(a.cli_new)}\n")


if __name__ == "__main__":
    main()
