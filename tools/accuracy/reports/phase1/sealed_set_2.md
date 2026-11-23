# Sealed set 2: pre-registration (written before the run)

Registered: 2026-11-22 10:19 (Africa/Lagos), before any clip of this set was generated or scored.
This directory is not under git here, so the record is this file plus a copy in the Project store (`adr/` neighbours), both written before the run.

- Seeds: 32001, 32002, 32003, 32004 (never used for dev, tuning or any earlier run; 600 step clips + 240 steady-vibrato clips)
- sha256 of the seed list "32001,32002,32003,32004": c8a8980b6e3cf9d0851e49733dd8be872d180b604ca4b9e61c5a0041ca5c0aaf
- Frozen binary: /tmp/frozen/intono-cli-gate2, sha256 720b9a118df3a4d3916339e03a4f39db87f212a99c22ac3b53bb22a21ee1dd06
- Source at the freeze (sha256):
  - dsp/src/notes_hmm.hpp f58401de71d162c5bea28f1ae8629b31e30d134f0e9569e8682016c8131da3be
  - dsp/src/notes.hpp 4986ec7bc4d5152fc896ebcdacaf4fdddf66a8a079d2b9626b8dc4bf9f97ad98
  - dsp/src/engine.cpp 09cad1047257cc55efa6f643fae8d4303b15f5fd2ab59a4772e63c81437153a1
  - tools/accuracy/ref/synth.py d72df1e2935f308273ebc5d86b676efbbe8c1cb6c32bdcd3184623ccd321bf8d
  - tools/accuracy/run_boundaries.py a6340fbc4118ca973d88fa9e415971f132baf4e4af4a09843246895014641a56
- Version under test: ADR 0004 including Amendment 2 (run-edge rule). Dev gates at the freeze: recall 1.000, precision 1.000, 0 steady false splits, boundary error p95 14.1 ms / max 19.8 ms, note-mean error median 0.00 / max 1.48 cents, delay max 318 ms; 70 unit tests pass.
- Gates (unchanged from ADR 0004): recall >= 0.995 and precision >= 0.995 for steps >= 60 cents with vibrato up to +-50 cents at 4-8 Hz; 0 false splits on steady wide vibrato; boundary error p95 <= 20 ms and max <= 100 ms; note-mean error <= 2 cents on every note and median <= 0.5 cents; summary delay <= 350 ms.
- Protocol: one run, `python3 -I run_boundaries.py --cli /tmp/frozen/intono-cli-gate2 --seeds gate2`; the script refuses a second run. Reported as measured. If any gate fails: no tuning against this set; fix on dev seeds and register a new set; this one is never reused.
