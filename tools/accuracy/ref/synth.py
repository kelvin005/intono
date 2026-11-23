"""Synthetic labelled set for the accuracy harness (architecture doc, Testing).

Generates sine, sawtooth and violin-like harmonic tones across G3-E7 with
deliberate detuning (±1 to ±50 c), vibrato (4-8 Hz, 10-80 c peak-to-peak) and
pink noise at 30/20/10 dB SNR. Every clip carries a per-sample f0 label and a
"centre" label (the pitch a player intends, i.e. without vibrato).
"""
from __future__ import annotations

from dataclasses import dataclass

import numpy as np

SR = 48000
PAD_S = 0.25
NOTE_S = 1.2
ATTACK_S = 0.04
RELEASE_S = 0.06


@dataclass
class Clip:
    name: str
    audio: np.ndarray
    f0: np.ndarray          # per-sample instantaneous f0 (0 where silent)
    f0_centre: np.ndarray   # per-sample intended pitch (0 where silent)
    note_on: float          # seconds
    note_off: float
    meta: dict


def midi_hz(m: float, a4: float = 440.0) -> float:
    return a4 * 2 ** ((m - 69) / 12)


def pink_noise(n: int, rng) -> np.ndarray:
    white = rng.standard_normal(n)
    X = np.fft.rfft(white)
    f = np.fft.rfftfreq(n)
    f[0] = f[1]
    x = np.fft.irfft(X / np.sqrt(f), n)
    return x / np.std(x)


def violin_amps(f0: float, n_harm: int) -> np.ndarray:
    """Rough violin spectrum: body resonances + bridge hill, weak fundamental low down."""
    k = np.arange(1, n_harm + 1)
    fk = k * f0
    amp = 1.0 / k**0.7
    for fc, g, bw in [(280, 2.0, 80), (460, 1.8, 120), (1000, 1.2, 300), (2700, 2.5, 700)]:
        amp *= 1 + g * np.exp(-0.5 * ((fk - fc) / bw) ** 2)
    if f0 < 300:                       # G-string: fundamental ~12 dB under 2nd
        amp[0] *= 0.25
    return amp / np.max(amp)


def render(f0_inst: np.ndarray, kind: str, rng) -> np.ndarray:
    phase = 2 * np.pi * np.cumsum(f0_inst) / SR
    f_mean = float(np.mean(f0_inst[f0_inst > 0]))
    nyq_harm = int((SR / 2 * 0.9) // f_mean)
    if kind == "sine":
        return np.sin(phase)
    if kind == "saw":
        n = max(1, nyq_harm)
        k = np.arange(1, n + 1)
        amps = 1.0 / k
    else:  # violin
        n = max(1, min(nyq_harm, 40))
        k = np.arange(1, n + 1)
        amps = violin_amps(f_mean, n)
    ph0 = rng.uniform(0, 2 * np.pi, n)
    out = np.zeros_like(phase)
    for i in range(n):
        out += amps[i] * np.sin(k[i] * phase + ph0[i])
    if kind == "violin":               # a little bow noise, band-limited by preprocessing anyway
        out += 0.01 * rng.standard_normal(out.size) * np.max(np.abs(out))
    return out


def make_clip(name, midi, detune_c, kind, vib_rate=0.0, vib_pp_c=0.0, snr_db=None, seed=0):
    rng = np.random.default_rng(seed)
    n_pad, n_note = int(PAD_S * SR), int(NOTE_S * SR)
    n = 2 * n_pad + n_note
    centre = midi_hz(midi + detune_c / 100.0)
    t = np.arange(n_note) / SR
    cents_dev = 0.5 * vib_pp_c * np.sin(2 * np.pi * vib_rate * t + rng.uniform(0, 2 * np.pi)) if vib_rate else 0 * t
    f_note = centre * 2 ** (cents_dev / 1200)
    tone = render(f_note, kind, rng)
    env = np.ones(n_note)
    na, nr = int(ATTACK_S * SR), int(RELEASE_S * SR)
    env[:na] = np.linspace(0, 1, na)
    env[-nr:] = np.linspace(1, 0, nr)
    tone *= env
    audio = np.zeros(n)
    audio[n_pad : n_pad + n_note] = tone / np.max(np.abs(tone)) * 0.5
    f0 = np.zeros(n)
    f0[n_pad : n_pad + n_note] = f_note
    f0c = np.zeros(n)
    f0c[n_pad : n_pad + n_note] = centre
    if snr_db is not None:
        sig_rms = np.sqrt(np.mean(audio[n_pad : n_pad + n_note] ** 2))
        noise = pink_noise(n, rng) * sig_rms / 10 ** (snr_db / 20)
        audio = audio + noise
    else:
        audio = audio + 1e-4 * rng.standard_normal(n)   # realistic mic floor
    meta = dict(midi=midi, detune_c=detune_c, kind=kind, vib_rate=vib_rate,
                vib_pp_c=vib_pp_c, snr_db=snr_db, centre_hz=centre)
    return Clip(name, audio.astype(np.float32), f0, f0c, PAD_S, PAD_S + NOTE_S, meta)


def build_set(seed: int = 7) -> list[Clip]:
    rng = np.random.default_rng(seed)
    clips = []
    pitches = list(range(55, 101, 3)) + [100]           # G3 .. E7
    s = 0
    for m in pitches:
        def det():
            return float(rng.choice([-1, 1]) * rng.uniform(1, 50))
        conds = [
            ("sine", dict(kind="sine")),
            ("saw", dict(kind="saw")),
            ("violin", dict(kind="violin")),
            ("violin_vib", dict(kind="violin", vib_rate=float(rng.uniform(4, 8)), vib_pp_c=float(rng.uniform(10, 80)))),
            ("violin_snr30", dict(kind="violin", snr_db=30)),
            ("violin_snr20", dict(kind="violin", snr_db=20)),
            ("violin_snr10", dict(kind="violin", snr_db=10)),
            ("violin_vib_snr20", dict(kind="violin", vib_rate=float(rng.uniform(4, 8)), vib_pp_c=float(rng.uniform(10, 80)), snr_db=20)),
        ]
        for cname, kw in conds:
            s += 1
            clips.append(make_clip(f"m{m}_{cname}", m, det(), seed=s, **kw))
    return clips


# ------------------------------------------------------------------ phrases (note-level ground truth)
@dataclass
class Phrase:
    name: str
    audio: np.ndarray
    notes: list          # dicts: t_on, t_off, midi, detune_c, vib_rate, vib_pp_c, legato (bool: joins the previous note)
    meta: dict


def make_phrase(name, spec, snr_db=None, seed=0):
    """spec: list of dicts(midi, detune_c, dur, gap, vib_rate, vib_pp_c). gap>0 is silence before the note (a bow
    change); gap==0 is a legato finger change: the pitch steps while the bow, and so the amplitude, carries on."""
    rng = np.random.default_rng(seed)
    lead, tail = 0.5, 0.35
    t = lead
    segs = []
    for i, n in enumerate(spec):
        legato = n["gap"] == 0 and i > 0
        t += n["gap"]
        segs.append((t, t + n["dur"], n, legato))
        t += n["dur"]
    total = int((t + tail) * SR)
    audio = np.zeros(total)
    truth = []
    for t0, t1, n, legato in segs:
        ns = int(round((t1 - t0) * SR))
        tt = np.arange(ns) / SR
        centre = midi_hz(n["midi"] + n["detune_c"] / 100.0)
        ph0 = n.get("vib_phase", None)
        ph0 = rng.uniform(0, 2 * np.pi) if ph0 is None else ph0       # phase at the note's first sample
        dev = 0.5 * n["vib_pp_c"] * np.sin(2 * np.pi * n["vib_rate"] * tt + ph0) if n["vib_rate"] else 0 * tt
        tone = render(centre * 2 ** (dev / 1200), "violin", rng)
        tone = tone / np.max(np.abs(tone)) * 0.5
        env = np.ones(ns)
        na, nr = int(ATTACK_S * SR), int(RELEASE_S * SR)
        if not legato:
            env[:na] = np.linspace(0, 1, na)
        else:
            env[: int(0.004 * SR)] = np.linspace(0.6, 1, int(0.004 * SR))       # near-instant finger change
        # a note is followed by legato iff the next one has gap==0; then it must not fade out
        nxt = segs[[s[2] is n for s in segs].index(True) + 1] if n is not segs[-1][2] else None
        if not (nxt is not None and nxt[3]):
            env[-nr:] = np.linspace(1, 0, nr)
        i0 = int(round(t0 * SR))
        audio[i0:i0 + ns] += tone * env
        truth.append(dict(t_on=t0, t_off=t1, midi=n["midi"], detune_c=n["detune_c"], vib_rate=n["vib_rate"],
                          vib_pp_c=n["vib_pp_c"], legato=bool(legato)))
    if snr_db is not None:
        sig = np.sqrt(np.mean(audio[audio != 0] ** 2))
        audio = audio + pink_noise(total, rng) * sig / 10 ** (snr_db / 20)
    else:
        audio = audio + 1e-4 * rng.standard_normal(total)
    return Phrase(name, audio.astype(np.float32), truth, dict(snr_db=snr_db))


def build_phrase_set(seed=21):
    """18 phrases x 8 notes: separated and legato notes, steps of 1-4 semitones, G3-E6, +-40 c detuning,
    some vibrato notes; clean, 20 dB and 10 dB SNR."""
    rng = np.random.default_rng(seed)
    out = []
    for k in range(18):
        m = int(rng.integers(57, 76))
        spec = []
        for i in range(8):
            step = int(rng.choice([-4, -3, -2, -1, 1, 2, 3, 4]))
            m = m + step if 55 <= m + step <= 88 else m - step     # always a different note: legato needs a pitch change
            vib = rng.random() < 0.4
            spec.append(dict(midi=m, detune_c=float(rng.uniform(-40, 40)), dur=float(rng.uniform(0.4, 0.85)),
                             gap=0.0 if (i > 0 and rng.random() < 0.5) else float(rng.uniform(0.12, 0.25)),
                             vib_rate=float(rng.uniform(4.5, 7.5)) if vib else 0.0,
                             vib_pp_c=float(rng.uniform(25, 70)) if vib else 0.0))
        snr = [None, 20, 10][k % 3]
        out.append(make_phrase(f"phrase{k:02d}" + ("" if snr is None else f"_snr{snr}"), spec, snr, seed=1000 + k))
    return out


# ------------------------------------------------------------------ boundary clips (ADR 0004)
def _vib(rng, p_on, phase_at_step_bin, nbins, dur, rate_out, is_end):
    """Vibrato +-(20..50) c at 4..8 Hz. The phase AT THE STEP INSTANT is stratified over nbins bins, so every phase is covered."""
    if rng.random() >= p_on:
        return dict(vib_rate=0.0, vib_pp_c=0.0)
    rate = float(rng.uniform(4, 8))
    ph_step = 2 * np.pi * (phase_at_step_bin + rng.random()) / nbins
    out = dict(vib_rate=rate, vib_pp_c=float(2 * rng.uniform(20, 50)))
    # note A: step is at its end (t = dur); note B: step is at its start (t = 0)
    out["vib_phase"] = (ph_step - 2 * np.pi * rate * dur) if is_end else ph_step
    return out


def build_boundary_set(seed, n=150, min_step_c=60.0):
    """Two-note legato clips. The step between the intended pitches is >= min_step_c and the notes are different ET notes;
    each note has vibrato up to +-50 c at 4-8 Hz with 85% probability; vibrato phase at the step is stratified over 16 bins
    for each note independently. Clean / 20 dB / 10 dB SNR in turn. Truth: one boundary at t_step."""
    rng = np.random.default_rng(seed)
    out = []
    for i in range(n):
        while True:
            mA = int(rng.integers(59, 80))                         # G3 (196 Hz) is the lowest note the detector supports
            k = int(rng.choice([-4, -3, -2, -1, 1, 2, 3, 4]))
            mB = mA + k
            dA, dB = float(rng.uniform(-40, 40)), float(rng.uniform(-40, 40))
            if abs(100 * k + dB - dA) >= min_step_c:
                break
        durA, durB = float(rng.uniform(0.8, 1.1)), float(rng.uniform(0.8, 1.0))
        a = dict(midi=mA, detune_c=dA, dur=durA, gap=0.0, **_vib(rng, 0.85, i % 16, 16, durA, None, True))
        b = dict(midi=mB, detune_c=dB, dur=durB, gap=0.0, **_vib(rng, 0.85, (i // 16 + 7 * i) % 16, 16, durB, None, False))
        snr = [None, 20, 10][i % 3]
        ph = make_phrase(f"step{seed}_{i:03d}", [a, b], snr, seed=seed * 1000 + i)
        ph.meta.update(step_c=100 * k + dB - dA, t_step=ph.notes[1]["t_on"])
        out.append(ph)
    return out


def build_steady_vibrato_set(seed, n=60):
    """Single 1.5 s notes with steady wide vibrato (+-35..50 c, 4-8 Hz), detune +-40 c: the false-split trap."""
    rng = np.random.default_rng(seed)
    out = []
    for i in range(n):
        spec = [dict(midi=int(rng.integers(55, 88)), detune_c=float(rng.uniform(-40, 40)), dur=1.5, gap=0.0,
                     vib_rate=float(rng.uniform(4, 8)), vib_pp_c=float(2 * rng.uniform(35, 50)),
                     vib_phase=float(rng.uniform(0, 2 * np.pi)))]
        out.append(make_phrase(f"steady{seed}_{i:03d}", spec, [None, 20, 10][i % 3], seed=seed * 1000 + i))
    return out


def build_short_run_set(seed, n=30, min_step_c=150.0, vib_prob=0.5):
    """Runs of 5 to 7 consecutive short legato notes (100-250 ms each, steps of 100-300 cents, random direction), the
    way a fast scale passage is played. Added after real-audio clip #1, where the engine lost the middle note of
    such a run (ADR 0004, 'Real clip #1 findings'): every earlier synthetic boundary test had one step per clip or
    notes of 0.4 s and more, so the change-point fit never saw two boundaries inside one look-ahead window.
    Roughly a third of the phrases get a bow dropout (a 30-70 ms gap) before one of the middle notes. Every centre step is at
    least `min_step_c` cents (detune redrawn until it is). Half of the notes get vibrato of +-15 to +-30 cents at 5-7 Hz."""
    rng = np.random.default_rng(seed)
    out = []
    for i in range(n):
        k = int(rng.integers(5, 8))
        m = int(rng.integers(62, 80))
        spec = []
        for j in range(k):
            dc = float(rng.uniform(-30, 30))
            if j:
                step = int(rng.choice([1, 2, 3])) * int(rng.choice([-1, 1]))
                if not 56 <= m + step <= 86:
                    step = -step                               # reflect at the ends of the range: no repeated pitch
                # the detune must make the centre step at least min_step_c: the detune of this note is drawn from the
                # interval that allows it (a 1-semitone step becomes 2 semitones if no detune does)
                d_prev, sg = spec[-1]["detune_c"], 1 if step > 0 else -1
                need = min_step_c - 100.0 * abs(step)          # sg * (dc - d_prev) must be at least this
                lo, hi = (max(-30.0, d_prev + need), 30.0) if sg > 0 else (-30.0, min(30.0, d_prev - need))
                if lo > hi:
                    step += sg
                    need = min_step_c - 100.0 * abs(step)
                    lo, hi = (max(-30.0, d_prev + need), 30.0) if sg > 0 else (-30.0, min(30.0, d_prev - need))
                dc = float(rng.uniform(lo, hi))
                m += step
            gap = float(rng.uniform(0.03, 0.07)) if (0 < j < k - 1 and rng.random() < 0.33 / max(1, k - 2) * 3) else 0.0
            vib = rng.random() < vib_prob
            spec.append(dict(midi=m, detune_c=dc, dur=float(rng.uniform(0.10, 0.25)), gap=gap,
                             vib_rate=float(rng.uniform(5.0, 7.0)) if vib else 0.0,
                             vib_pp_c=float(2 * rng.uniform(15.0, 30.0)) if vib else 0.0))
        # a held first and last note so the run has well-defined edges, as in the real passage
        spec[0]["dur"], spec[-1]["dur"] = float(rng.uniform(0.25, 0.4)), float(rng.uniform(0.25, 0.4))
        out.append(make_phrase(f"shortrun{seed}_{i}", spec, snr_db=float(rng.uniform(20, 35)), seed=int(rng.integers(1 << 30))))
    return out
