# Sealed set 4: pre-registration (written before the run)

Registered: 2026-11-22 (Africa/Lagos), before any clip of this set was generated or scored. Sets 1 to 3 are spent (set 3 passed the version
with Amendments 2 and 3). This set certifies ADR 0004 Amendment 4 against the original boundary gates. Not under git here: this file plus a
copy in the Project store, both written before the run.

- Seeds: 35001, 35002, 35003, 35004 (never used for dev, tuning or any earlier run; 600 step clips + 240 steady-vibrato clips; same generator as sets 1 to 3, `build_boundary_set` / `build_steady_vibrato_set` unchanged)
- sha256 of the seed list "35001,35002,35003,35004": 7754b293e40a7925b0f8205810b8e39bc476be05335e29cbb0c17a799b50b58f
- Frozen binary: /tmp/frozen/intono-cli-gate4, sha256 0396631400395a53387d2305dbd91538d09d263a914fcca53a7a0dfda5060a50
- Source at the freeze (sha256):
  - dsp/src/notes_hmm.hpp e34cd7774de802443258be5df7c22bbd5e479eb1427e5ef527adca100fdc7d25
  - dsp/src/notes.hpp 4986ec7bc4d5152fc896ebcdacaf4fdddf66a8a079d2b9626b8dc4bf9f97ad98
  - dsp/src/engine.cpp 09cad1047257cc55efa6f643fae8d4303b15f5fd2ab59a4772e63c81437153a1
  - tools/accuracy/ref/synth.py 162a48efca0b97ec56c4435991a44102b496410a3b1dd97cf2f33aff7f9862fa (only `build_short_run_set` changed since set 3)
  - tools/accuracy/run_boundaries.py 9e66189397f68b2f8c8a4169ffe50e5b2eb8291f51f8e0c8e02c6a806450bd91 (registry only)
- Version under test: ADR 0004 including Amendments 2, 3 and 4. Dev evidence at the freeze: 74 unit tests; seeds 9101 to 9108: recall 1200/1200, 0 spurious, 0 steady false splits, boundary error p95 11.8 / max 20.2 ms, note-mean error max 1.48 cents, delay max 329 ms.
- Gates, unchanged from set 3: recall >= 0.995 and precision >= 0.995 for steps >= 60 cents with vibrato up to +-50 cents at 4-8 Hz; 0 false splits on steady wide vibrato; boundary error p95 <= 20 ms and max <= 100 ms; note-mean error <= 2 cents on every note and median <= 0.5 cents; summary delay <= 350 ms.
- Protocol: one run, `python3 -I run_boundaries.py --cli /tmp/frozen/intono-cli-gate4 --seeds gate4`; the script refuses a second run. Reported as measured. If any gate fails: no tuning against this set; fix on dev seeds and register a new set; this one is never reused.
