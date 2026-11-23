# Sealed set 3: pre-registration (written before the run)

Registered: 2026-11-22 10:32 (Africa/Lagos), before any clip of this set was generated or scored.
Set 2 (32001 to 32004) failed and is spent (see sealed_set_2.md and ADR 0004); it is not reused. This directory is not under
git here, so the record is this file plus a copy in the Project store, both written before the run.

- Seeds: 33001, 33002, 33003, 33004 (never used for dev, tuning or any earlier run; 600 step clips + 240 steady-vibrato clips)
- sha256 of the seed list "33001,33002,33003,33004": 21227fc7aa2402f357d9a63d28db213abade1d49f2b3e98651dc11a2f2868677
- Frozen binary: /tmp/frozen/intono-cli-gate3, sha256 8fa82ac4a3000dd2b22b772e0b3e3fbbe08757f7eeeb55f399d30e51f786f071
- Source at the freeze (sha256):
  - dsp/src/notes_hmm.hpp f3c95b0689205183179a54e9152805eed5771f97d8c8acc9ecf7cd0c058276ec
  - dsp/src/notes.hpp 4986ec7bc4d5152fc896ebcdacaf4fdddf66a8a079d2b9626b8dc4bf9f97ad98
  - dsp/src/engine.cpp 09cad1047257cc55efa6f643fae8d4303b15f5fd2ab59a4772e63c81437153a1
  - tools/accuracy/ref/synth.py d72df1e2935f308273ebc5d86b676efbbe8c1cb6c32bdcd3184623ccd321bf8d
  - tools/accuracy/run_boundaries.py 8c996dbf78fe4037d982c4a5ebac50dac3008cbc394f8c4b61c8e8c131509fc6
- Version under test: ADR 0004 including Amendments 2 and 3. Dev evidence at the freeze: 71 unit tests; seeds 9101, 9102 and 9103 to 9108 (1800 notes): recall 1.000, 0 spurious (60 ms start window), 0 steady false splits, boundary error p95 12.1 / max 20.2 ms, note-mean error max 1.26 cents (9101, 9102: 1.48), delay max 329 ms.
- Harness change since set 2: the spurious-note window at the start of the first note is 60 ms instead of 150 ms (ADR 0004, Amendment 3, item 3). Gates are unchanged:
  recall >= 0.995 and precision >= 0.995 for steps >= 60 cents with vibrato up to +-50 cents at 4-8 Hz; 0 false splits on steady wide vibrato; boundary error p95 <= 20 ms and max <= 100 ms; note-mean error <= 2 cents on every note and median <= 0.5 cents; summary delay <= 350 ms.
- Protocol: one run, `python3 -I run_boundaries.py --cli /tmp/frozen/intono-cli-gate3 --seeds gate3`; the script refuses a second run. Reported as measured. If any gate fails: no tuning against this set; fix on dev seeds and register a new set; this one is never reused.
