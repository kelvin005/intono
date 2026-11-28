"""Semitone set (Kelechi, 2026-11-28): semitone steps played 20 to 40 cents flat or sharp, so the centre step between neighbours is
60 to 80 cents, in scale mode. This is ADR 0004's other Phase 3 known limit, "60 to 80 cent steps" (a student 30 cents flat); the
p3gate set covered 100 to 150 cent steps only.

Each phrase is a run of 5 to 7 legato notes, built like build_short_run_set:
  - middle notes 100 to 250 ms, the first and last held 250 to 400 ms;
  - a bow dropout (30 to 70 ms) before a middle note in about a third of the phrases;
  - half of the notes with vibrato of +-15 to +-30 cents at 5 to 7 Hz;
  - SNR 20 to 35 dB.
Every step is one semitone (direction random), and its CENTRE size is drawn from 60 to 80 cents. So each note's detune moves 20 to
40 cents against the step from the previous note's. The direction is flipped whenever that would take the detune outside +-40 cents,
so every note stays nearest its own semitone. Every note's smaller adjacent step is therefore 60 to 80 cents.

The engine is given each phrase's sequence (its MIDI notes) as the expected sequence, as the scale screen does.

Scoring:
  - a truth note is found if an engine note has its MIDI number and an onset within 80 ms (each engine note used once);
  - an engine note that matches no truth note is INVENTED.
Gates (Kelechi, 2026-11-28): recall >= 0.99 of all truth notes; invented notes <= 0.5 % of truth notes. Recall of the 100 to 250 ms
notes is reported too (not gated).

This file holds the generator and the scoring, so both are fixed by its hash at registration. synth.py is only called (make_phrase),
not changed, so its registered hash stays valid.
"""
import numpy as np

import synth

ONSET_TOL = 0.08
D_MAX = 40.0


def build_semitone_set(seed, n=30):
    rng = np.random.default_rng(seed)
    out = []
    for i in range(n):
        k = int(rng.integers(5, 8))
        m = int(rng.integers(62, 80))
        d = float(rng.uniform(-20, 20))
        spec = []
        for j in range(k):
            if j:
                delta = 100.0 - float(rng.uniform(60.0, 80.0))   # how far the centre step falls short of 100 cents
                sg = int(rng.choice([-1, 1]))
                if not (56 <= m + sg <= 86) or abs(d - sg * delta) > D_MAX:
                    sg = -sg                                       # the other direction keeps the note in range and in its semitone
                m += sg
                d -= sg * delta                                    # up: this note lower relative to its semitone; down: higher
            gap = float(rng.uniform(0.03, 0.07)) if (0 < j < k - 1 and rng.random() < 0.33 / max(1, k - 2) * 3) else 0.0
            vib = rng.random() < 0.5
            spec.append(dict(midi=m, detune_c=d, dur=float(rng.uniform(0.10, 0.25)), gap=gap,
                             vib_rate=float(rng.uniform(5.0, 7.0)) if vib else 0.0,
                             vib_pp_c=float(2 * rng.uniform(15.0, 30.0)) if vib else 0.0))
        spec[0]["dur"], spec[-1]["dur"] = float(rng.uniform(0.25, 0.4)), float(rng.uniform(0.25, 0.4))
        out.append(synth.make_phrase(f"semitone{seed}_{i}", spec, snr_db=float(rng.uniform(20, 35)), seed=int(rng.integers(1 << 30))))
    return out


MAJOR_STEPS = [2, 2, 1, 2, 2, 2, 1]


def build_realistic_set(seed, n=30):
    """Set (a), realistic (Kelechi, 2026-11-28): a beginner's scale passage. 6 to 8 notes of a major scale (up or down, from a random
    tonic, wrapping through the scale's own step pattern: whole and half steps), each note 100 to 250 ms (the first and last 250 to 400),
    EVERY note detuned by an independent amount of 0 to 40 cents, flat or sharp at random (so a half step can be as small as 20 cents).
    Bow dropout, vibrato and SNR as in build_semitone_set. The engine is given the phrase's MIDI sequence as the expected sequence."""
    rng = np.random.default_rng(seed)
    out = []
    for i in range(n):
        k = int(rng.integers(6, 9))
        up = bool(rng.integers(0, 2))
        pos = int(rng.integers(0, 7))
        m = int(rng.integers(57, 74)) if up else int(rng.integers(70, 85))   # the whole phrase stays in 56..86 (G3 is 55: violin range)
        spec = []
        for j in range(k):
            if j:
                st = MAJOR_STEPS[pos % 7] if up else MAJOR_STEPS[(pos - 1) % 7]
                m += st if up else -st
                pos += 1 if up else -1
            d = float(rng.uniform(0, D_MAX)) * float(rng.choice([-1, 1]))
            gap = float(rng.uniform(0.03, 0.07)) if (0 < j < k - 1 and rng.random() < 0.33 / max(1, k - 2) * 3) else 0.0
            vib = rng.random() < 0.5
            spec.append(dict(midi=m, detune_c=d, dur=float(rng.uniform(0.10, 0.25)), gap=gap,
                             vib_rate=float(rng.uniform(5.0, 7.0)) if vib else 0.0,
                             vib_pp_c=float(2 * rng.uniform(15.0, 30.0)) if vib else 0.0))
        spec[0]["dur"], spec[-1]["dur"] = float(rng.uniform(0.25, 0.4)), float(rng.uniform(0.25, 0.4))
        out.append(synth.make_phrase(f"realistic{seed}_{i}", spec, snr_db=float(rng.uniform(20, 35)), seed=int(rng.integers(1 << 30))))
    return out


def centre_steps(ph):
    """The centre step in cents between each pair of neighbours."""
    c = [100.0 * t["midi"] + t["detune_c"] for t in ph.notes]
    return [abs(b - a) for a, b in zip(c, c[1:])]


def score(results):
    """results: [(phrase, engine_notes)], engine_notes = [(t_start, midi)]. Returns counts and rates."""
    truth = found = invented = short_n = short_found = 0
    for ph, est in results:
        used = set()
        for t in ph.notes:
            truth += 1
            hit = False
            for j, (t0, midi) in enumerate(est):
                if j not in used and midi == t["midi"] and abs(t0 - t["t_on"]) < ONSET_TOL:
                    used.add(j)
                    hit = True
                    break
            found += hit
            if 0.10 <= t["t_off"] - t["t_on"] <= 0.25:
                short_n += 1
                short_found += hit
        invented += len(est) - len(used)
    return dict(truth=truth, found=found, recall=found / max(truth, 1), invented=invented,
                invented_rate=invented / max(truth, 1), short=short_n, short_found=short_found,
                recall_short=short_found / max(short_n, 1))
