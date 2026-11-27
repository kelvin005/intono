"""Deviation set for score-informed segmentation (ADR 0014, second sealed gate; Kelechi 2026-11-27).

In scale mode the engine is told what should come next. This set checks that it does not INVENT the expected note when the player does
something else. Each phrase is a 10-note scale fragment (the expected sequence E, given to the engine) played with exactly ONE deviation
(the audio P), the four kinds in turn so they are balanced:

  wrong     P[p] is 1 or 2 semitones away from E[p]          invented: E[p] reported within +-80 ms of the wrong note's onset
  skip      E[p] is not played                                invented: E[p] reported starting between the notes around the gap
  repeat    E[p] is played twice (re-bowed, 30-70 ms gap)     invented: E[p+1] reported within +-80 ms of the repeat's onset
  offscale  a note not in E is inserted before E[p]           invented: E[p] reported within +-80 ms of the inserted note's onset

Gates (ADR 0014): invented-expected-note rate <= 0.5 % of deviations; recall of the played deviation notes (the wrong note, the
repeat, the off-scale note) >= 0.98 (same MIDI number, onset within 80 ms, each engine note used once).

This file holds the generator and the scoring, so both are fixed by its hash at registration. synth.py is only called (make_phrase), not
changed, so its registered hash for the p3gate set stays valid.
"""
import numpy as np

import synth

MAJOR = [2, 2, 1, 2, 2, 2, 1]
KINDS = ("wrong", "skip", "repeat", "offscale")
N_NOTES = 10
ONSET_TOL = 0.08


def _expected(rng):
    """A 10-note diatonic fragment: up from a random degree, turning down once near the top, inside 56..86 (MIDI)."""
    deg = int(rng.integers(0, 7))
    m = int(rng.integers(60, 72))
    up = int(rng.integers(5, 8))          # notes before the turn
    seq = [m]
    d = deg
    for i in range(1, N_NOTES):
        if i < up:
            m += MAJOR[d % 7]
            d += 1
        else:
            d -= 1
            m -= MAJOR[d % 7]
        seq.append(m)
    assert all(56 <= x <= 86 for x in seq), seq
    return seq


def _note(rng, midi, gap=0.0):
    vib = rng.random() < 0.5
    return dict(midi=int(midi), detune_c=float(rng.uniform(-20, 20)), dur=float(rng.uniform(0.12, 0.40)), gap=gap,
                vib_rate=float(rng.uniform(5.0, 7.0)) if vib else 0.0, vib_pp_c=float(2 * rng.uniform(10.0, 25.0)) if vib else 0.0)


def build_deviation_set(seed, n=64):
    """[(phrase, expected, event)] for one seed. phrase: synth.Phrase of the PLAYED notes; expected: the MIDI list given to the
    engine; event: dict(kind, p, invented_midi, window=(t0, t1), played=index of the deviation note in phrase.notes or None)."""
    rng = np.random.default_rng(seed)
    out = []
    for i in range(n):
        kind = KINDS[i % 4]
        E = _expected(rng)
        p = int(rng.integers(2, N_NOTES - 2))          # never the first or last two notes
        if kind == "skip":
            while E[p - 1] == E[p + 1]:                # skipping the top of a turn would leave two legato notes of one pitch
                p = int(rng.integers(2, N_NOTES - 2))
        spec, dev_idx = [], None
        for j, m in enumerate(E):
            if j == p:
                if kind == "wrong":
                    choices = [d for d in (-2, -1, 1, 2) if m + d not in (E[j - 1], E[j + 1])]
                    spec.append(_note(rng, m + int(rng.choice(choices))))
                    dev_idx = len(spec) - 1
                    continue
                if kind == "skip":
                    continue
                if kind == "offscale":
                    pool = [x for x in range(min(E[j - 1], m) - 2, max(E[j - 1], m) + 3) if x not in E]
                    spec.append(_note(rng, int(rng.choice(pool))))
                    dev_idx = len(spec) - 1
                    spec.append(_note(rng, m))
                    continue
                if kind == "repeat":
                    spec.append(_note(rng, m))
                    spec.append(_note(rng, m, gap=float(rng.uniform(0.03, 0.07))))
                    dev_idx = len(spec) - 1
                    continue
            spec.append(_note(rng, m))
        spec[0]["dur"], spec[-1]["dur"] = float(rng.uniform(0.25, 0.4)), float(rng.uniform(0.25, 0.4))
        ph = synth.make_phrase(f"dev{seed}_{i}_{kind}", spec, snr_db=float(rng.uniform(20, 35)), seed=int(rng.integers(1 << 30)))
        T = ph.notes
        if kind == "wrong":
            ev = dict(invented_midi=E[p], window=(T[dev_idx]["t_on"] - ONSET_TOL, T[dev_idx]["t_on"] + ONSET_TOL))
        elif kind == "skip":
            before, after = T[p - 1], T[p]                 # the notes played around the skipped one
            ev = dict(invented_midi=E[p], window=(before["t_on"] + ONSET_TOL, after["t_on"] + ONSET_TOL))
        elif kind == "repeat":
            ev = dict(invented_midi=E[p + 1], window=(T[dev_idx]["t_on"] - ONSET_TOL, T[dev_idx]["t_on"] + ONSET_TOL))
        else:
            ev = dict(invented_midi=E[p], window=(T[dev_idx]["t_on"] - ONSET_TOL, T[dev_idx]["t_on"] + ONSET_TOL))
        ev.update(kind=kind, p=p, played=dev_idx)
        out.append((ph, E, ev))
    return out


def score(results):
    """results: [(phrase, expected, event, engine_notes)], engine_notes = [(t_start, midi)]. Returns the counts and the two rates."""
    dev = invented = played = found = 0
    by_kind = {k: [0, 0, 0, 0] for k in KINDS}        # deviations, invented, played deviation notes, found
    for ph, E, ev, est in results:
        dev += 1
        bk = by_kind[ev["kind"]]
        bk[0] += 1
        t0, t1 = ev["window"]
        inv = any(m == ev["invented_midi"] and t0 <= t <= t1 for t, m in est)
        invented += inv
        bk[1] += inv
        if ev["played"] is not None:
            truth = ph.notes[ev["played"]]
            played += 1
            bk[2] += 1
            hit = any(m == truth["midi"] and abs(t - truth["t_on"]) < ONSET_TOL for t, m in est)
            found += hit
            bk[3] += hit
    return dict(deviations=dev, invented=invented, invented_rate=invented / max(dev, 1), played=played, found=found,
                recall=found / max(played, 1), by_kind=by_kind)
