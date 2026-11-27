#!/usr/bin/env python3
"""Generates app/assets/scales/beginner.json: the Phase 3 scale definitions (ADR 0011), as data.

  python tools/scales/gen_scales.py [--check]      # --check: exit 1 if the committed file differs (CI)

Keys (beginner first): G, D, A, C, F major; A, D, E minor (natural, harmonic, melodic). Each scale starts on the lowest tonic at or above
the open G string and is given in 1 octave, and in 2 octaves where both octaves fit first position (G3 to B5). A scale is the ascending
notes then the descending notes, the top tonic once. Melodic minor ascends with raised 6th and 7th and descends natural.

First-position fingering, per note: the lowest string on which the note is 0 to 6 semitones above the open string (an open string is
preferred to a 4th finger), the E string up to +7 (B5, 4th finger). Finger: 0 open, 1 (+1 low, +2), 2 (+3 low, +4 high), 3 (+5, +6 high),
4 (+7). Spelling follows the key: the letters run from the tonic's letter, the accidental is whatever makes the pitch.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "app", "assets", "scales", "beginner.json")

STRINGS = [("G", 55), ("D", 62), ("A", 69), ("E", 76)]
LOW, HIGH = 55, 83                      # G3 .. B5: first position, 4th finger on E
LETTERS = "CDEFGAB"
LETTER_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
FINGER = {0: (0, None), 1: (1, "low"), 2: (1, None), 3: (2, "low"), 4: (2, "high"), 5: (3, None), 6: (3, "high"), 7: (4, None)}

STEPS = {
    "major": ([2, 2, 1, 2, 2, 2, 1], None),
    "natural_minor": ([2, 1, 2, 2, 1, 2, 2], None),
    "harmonic_minor": ([2, 1, 2, 2, 1, 3, 1], None),
    "melodic_minor": ([2, 1, 2, 2, 2, 2, 1], [2, 1, 2, 2, 1, 2, 2]),   # up, down (natural)
}
KEYS = [("G", "major"), ("D", "major"), ("A", "major"), ("C", "major"), ("F", "major"),
        ("A", "minor"), ("D", "minor"), ("E", "minor")]


def name(midi, letter):
    pc = midi % 12
    d = (pc - LETTER_PC[letter] + 6) % 12 - 6          # -2..+2
    acc = {-2: "bb", -1: "b", 0: "", 1: "#", 2: "##"}[d]
    octave = (midi - LETTER_PC[letter] - d) // 12 - 1
    return f"{letter}{acc}{octave}"


def fingering(midi):
    for s, (sname, open_) in enumerate(STRINGS):
        off = midi - open_
        last = s == len(STRINGS) - 1
        if 0 <= off <= (7 if last else 6):
            f, kind = FINGER[off]
            d = {"string": sname, "finger": f}
            if kind:
                d["placement"] = kind
            return d
    raise ValueError(f"midi {midi} is outside first position")


def degrees(tonic_midi, tonic_letter, steps):
    """[(midi, letter)] for one octave from the tonic, 8 notes."""
    out = [(tonic_midi, tonic_letter)]
    li = LETTERS.index(tonic_letter)
    m = tonic_midi
    for k, st in enumerate(steps):
        m += st
        out.append((m, LETTERS[(li + k + 1) % 7]))
    return out


def build(tonic, mode, kind, octaves):
    pc = LETTER_PC[tonic]
    tonic_midi = next(m for m in range(LOW, LOW + 12) if m % 12 == pc)
    up_steps, down_steps = STEPS[kind]
    up, down = [], []
    for o in range(octaves):
        oct_up = degrees(tonic_midi + 12 * o, tonic, up_steps)
        up += oct_up if o == 0 else oct_up[1:]
        oct_dn = degrees(tonic_midi + 12 * o, tonic, down_steps or up_steps)
        down = (oct_dn if o == 0 else oct_dn[1:]) if o == 0 else down + oct_dn[1:]
    if down_steps is None:
        down = up
    seq = up + list(reversed(down))[1:]   # top tonic once
    if max(m for m, _ in seq) > HIGH:
        return None
    notes = [{"midi": m, "name": name(m, l), **fingering(m)} for m, l in seq]
    key_name = f"{tonic} {'major' if mode == 'major' else 'minor'}"
    label = {"major": "major", "natural_minor": "natural minor", "harmonic_minor": "harmonic minor", "melodic_minor": "melodic minor"}[kind]
    return {
        "id": f"{tonic.lower()}_{kind}_{octaves}oct",
        "title": f"{tonic} {label}, {octaves} octave{'s' if octaves > 1 else ''}",
        "key": key_name,
        "type": kind,
        "octaves": octaves,
        "position": 1,
        "ascending_count": len(up),
        "notes": notes,
    }


def generate():
    scales = []
    for tonic, mode in KEYS:
        kinds = ["major"] if mode == "major" else ["natural_minor", "harmonic_minor", "melodic_minor"]
        for kind in kinds:
            for octaves in (1, 2):
                s = build(tonic, mode, kind, octaves)
                if s:
                    scales.append(s)
    return {
        "format": 1,
        "generator": "tools/scales/gen_scales.py",
        "tuning_reference": "notes are MIDI numbers in 12-TET names; the A4 reference and the tuning system are applied by the grader",
        "first_position_range": {"low": LOW, "high": HIGH},
        "strings": [{"name": n, "open_midi": m} for n, m in STRINGS],
        "scales": scales,
    }


def main():
    text = json.dumps(generate(), indent=1, ensure_ascii=False) + "\n"
    if "--check" in sys.argv:
        old = open(OUT).read() if os.path.exists(OUT) else ""
        if old != text:
            print(f"{OUT} is not what gen_scales.py generates: run it and commit the result")
            sys.exit(1)
        print("scales up to date")
        return
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write(text)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
