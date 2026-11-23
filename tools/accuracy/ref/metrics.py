"""Accuracy metrics from the architecture doc (Testing > DSP accuracy harness)."""
from __future__ import annotations

import numpy as np
import mir_eval

ATTACK_GUARD_S = 0.08 + 0.011     # note must be stable 80 ms; plus half-window
RELEASE_GUARD_S = 0.06 + 0.011
CONTOUR_FILL_S = 0.30             # centre pitch needs a filled 250 ms contour
SILENCE_GUARD_S = 0.03


def cents_err(est_hz, ref_hz):
    return 1200 * np.log2(np.maximum(est_hz, 1e-9) / np.maximum(ref_hz, 1e-9))


def clip_frames(t, clip):
    """Labels sampled at frame-centre times plus masks."""
    idx = np.clip((t * 48000).astype(int), 0, len(clip.f0) - 1)
    ref = clip.f0[idx]
    ref_c = clip.f0_centre[idx]
    stable = (t >= clip.note_on + ATTACK_GUARD_S) & (t <= clip.note_off - RELEASE_GUARD_S)
    centre_ok = (t >= clip.note_on + CONTOUR_FILL_S) & (t <= clip.note_off - RELEASE_GUARD_S)
    silent = (t < clip.note_on - SILENCE_GUARD_S) | (t > clip.note_off + SILENCE_GUARD_S)
    return ref, ref_c, stable, centre_ok, silent


def score_clip(t, est_hz, est_centre, voiced, clip):
    ref, ref_c, stable, centre_ok, silent = clip_frames(t, clip)
    vib = clip.meta["vib_rate"] > 0
    out = {}
    # raw pitch accuracy over stable frames (mir_eval, 50 c tolerance)
    rv = np.ones(stable.sum(), bool)
    ev = voiced[stable] & (est_hz[stable] > 0)
    rc = mir_eval.melody.hz2cents(ref[stable])
    ec = mir_eval.melody.hz2cents(np.where(ev, est_hz[stable], 0.0))
    out["n_stable"] = int(stable.sum())
    out["rpa_hits"] = float(mir_eval.melody.raw_pitch_accuracy(rv, rc, ev, ec, 50) * stable.sum())

    e = cents_err(est_hz[stable], ref[stable])
    valid = ev
    gross = valid & (np.abs(e) > 50)
    octave = valid & (np.abs(np.abs(e) - 1200) < 50)
    out["n_valid"] = int(valid.sum())
    out["gross"] = int(gross.sum())
    out["octave"] = int(octave.sum())
    good = valid & ~gross
    # frame-level abs error (instantaneous) on non-vibrato clips
    out["abs_err_frame"] = np.abs(e[good]).tolist() if not vib else []

    # displayed centre pitch error vs intended pitch
    cm = centre_ok & voiced & (est_centre > 0)
    ce = cents_err(est_centre[cm], ref_c[cm])
    ce = ce[np.abs(ce) <= 50]
    key = "abs_err_centre_vib" if vib else "abs_err_centre_stable"
    out[key] = np.abs(ce).tolist()

    out["n_silent"] = int(silent.sum())
    out["false_alarm"] = int((voiced[silent] & (est_hz[silent] > 0)).sum())
    return out


def aggregate(rows):
    def cat(k):
        v = [x for r in rows for x in r.get(k, [])]
        return np.array(v) if v else np.array([np.nan])

    n_stable = sum(r["n_stable"] for r in rows)
    n_valid = sum(r["n_valid"] for r in rows)
    fe, cs, cv = cat("abs_err_frame"), cat("abs_err_centre_stable"), cat("abs_err_centre_vib")
    return {
        "raw_pitch_accuracy_pct": 100 * sum(r["rpa_hits"] for r in rows) / max(n_stable, 1),
        "gross_error_pct": 100 * sum(r["gross"] for r in rows) / max(n_valid, 1),
        "octave_error_pct": 100 * sum(r["octave"] for r in rows) / max(n_valid, 1),
        "voicing_recall_pct": 100 * n_valid / max(n_stable, 1),
        "cents_mae_frame_stable": float(np.nanmean(fe)),
        "cents_p95_frame_stable": float(np.nanpercentile(fe, 95)),
        "cents_mae_centre_stable": float(np.nanmean(cs)),
        "cents_mae_centre_vibrato": float(np.nanmean(cv)),
        "voicing_false_alarm_pct": 100 * sum(r["false_alarm"] for r in rows) / max(sum(r["n_silent"] for r in rows), 1),
    }


# ------------------------------------------------------------------ note-level metrics (ADR 0003)
NOTE_ONSET_TOL_S = 0.05      # mir_eval transcription default
NOTE_PITCH_TOL_C = 50.0


def match_notes(truth, est):
    """Greedy one-to-one matching: same ET note number (est.midi_note), est start within 50 ms of the true onset."""
    used, pairs = set(), []
    for i, g in enumerate(truth):
        best, bd = None, 1e9
        for j, e in enumerate(est):
            if j in used or e.midi_note != g["midi"]:
                continue
            d = abs(e.t_start - g["t_on"])
            if d <= NOTE_ONSET_TOL_S and d < bd:
                best, bd = j, d
        if best is not None:
            used.add(best)
            pairs.append((i, best))
    return pairs


def score_notes(truth, est):
    """Per-phrase raw counts and error lists; aggregate_notes() turns them into rates."""
    pairs = match_notes(truth, est)
    out = dict(n_true=len(truth), n_est=len(est), n_match=len(pairs))
    err_n, err_v, on_err, off_err, wrong_midi = [], [], [], [], 0
    for i, j in pairs:
        g, e = truth[i], est[j]
        d = e.mean_cents - g["detune_c"]
        (err_v if g["vib_rate"] > 0 else err_n).append(abs(d))
        on_err.append(1000 * (e.t_start - g["t_on"]))
        off_err.append(1000 * (e.t_end - g["t_off"]))
    # a matched-by-time note with the wrong midi number is a pitch error, not just a miss
    for g in truth:
        if any(abs(e.t_start - g["t_on"]) <= NOTE_ONSET_TOL_S and e.midi_note != g["midi"] for e in est):
            wrong_midi += 1
    out.update(abs_err_cents=err_n, abs_err_cents_vib=err_v, onset_err_ms=on_err, offset_err_ms=off_err, wrong_midi=wrong_midi)
    return out


def aggregate_notes(rows):
    n_true, n_est, n_match = (sum(r[k] for r in rows) for k in ("n_true", "n_est", "n_match"))
    cat = lambda k: np.array([x for r in rows for x in r[k]] or [np.nan])
    en, ev, on, off = cat("abs_err_cents"), cat("abs_err_cents_vib"), cat("onset_err_ms"), cat("offset_err_ms")
    prec, rec = n_match / max(n_est, 1), n_match / max(n_true, 1)
    return {
        "note_precision": prec, "note_recall": rec, "note_f1": 2 * prec * rec / max(prec + rec, 1e-9),
        "note_wrong_midi": sum(r["wrong_midi"] for r in rows), "note_count_true": n_true, "note_count_est": n_est,
        "note_cents_mae": float(np.nanmean(en)), "note_cents_p95": float(np.nanpercentile(en, 95)),
        "note_cents_mae_vibrato": float(np.nanmean(ev)),
        "note_onset_mae_ms": float(np.nanmean(np.abs(on))), "note_offset_mae_ms": float(np.nanmean(np.abs(off))),
    }
