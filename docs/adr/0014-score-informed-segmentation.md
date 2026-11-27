# ADR 0014: Score-informed segmentation in scale mode (the hard Phase 3 gate)

Status: **Proposed** (2026-11-27). The gate's sealed set is pre-registered in `docs/adr/sealed-p3gate-preregistration.md` before any of
this exists. DSP change (in response to the recorded known limit, ADR 0004) and C API change: needs Kelechi's "merge" before
implementation starts, and again for the implementation PR.

## Context

The note HMM (ADR 0004) misses short notes next to a small step: on the informational sealed run (sr1info) it recovered 0.924 of notes
with a 100 to 130 cent neighbour step and 0.979 at 130 to 150 cents. The cause is the HMM's emission and switching cost: a 100 to 250 ms
note 100 to 150 cents from its neighbour does not pay for the switch (`kHmmSwitch` = 24, tolerance 50 cents, sigma 25) before the next
note arrives. In free play nothing better is known. **In scale mode the app knows what comes next** (ADR 0011): the hard gate is to use
that, and reach recall >= 0.995 on those notes.

## Decision proposed

```
UI thread                          worker thread (ADR 0008)                         unchanged
intono_set_expected(e, midi[], n) ─► expected[] + cursor k ─► note HMM: switch cost  ─► intono_read_notes
   (scale screen, on Start)          (k advances as notes     into expected[k+1] is      (same records,
   n = 0: free mode, as today        are emitted)              kHmmSwitchExpected < 24)   same delay)
```

1. **C API, one function** (the contract change; `intono.h`):
   `void intono_set_expected(intono_engine* e, const int* midi_notes, int n);` UI thread only. Copies up to 128 MIDI numbers into
   preallocated storage; `n = 0` returns to free mode. Handed to the worker lock-free (double buffer and an atomic generation; the worker
   picks it up between records). Nothing allocates, nothing locks, nothing new on the audio thread.
2. **Cursor:** the worker keeps `k`, the index of the expected note being played. When a note is emitted with `midi == expected[k]`, `k`
   advances; with `midi == expected[k+1]` (one note missed), `k` advances by two; anything else (a wrong or extra note) leaves `k`. At most
   one skip, so a run of wrong notes cannot drag the cursor away.
3. **The only change to decoding:** the cost of switching from the state of `expected[k]` into the state of `expected[k+1]` is
   `kHmmSwitchExpected` instead of `kHmmSwitch` (24). Emission, tolerance, sigma, the fixed lag, the change-point fit and the glitch rule
   are unchanged. **One new parameter**, chosen on dev seeds 9501 to 9516 only, never on the sealed set.
4. **Free mode is unchanged byte for byte:** with no expected sequence the decoder runs exactly as today (`bit-identity-vs-phase1`, the
   golden manifest, G7).
5. **Note delay unchanged** (same lag), so the 350 ms note-delay gate is unaffected.
6. **CLI:** `intono-cli file.wav --notes 1 --expected 62,64,66,...` for the runner. The runner's scale mode passes each phrase's truth
   sequence, and the p3gate set is run once as registered.

## Risks and the checks for them (dev seeds, before the sealed run)

- **Hallucinating the expected note** when the player plays something else or stays on a note: a lower switch cost must not invent the
  next scale note. Dev check: phrases where 10 % of notes deviate from the expected sequence (a semitone off, a repeated note, a skipped
  note). The expected note must not be reported where it was not played more often than free mode reports extra notes on the same
  phrases. Question 1 asks whether this becomes a sealed gate too.
- **Losing the cursor:** after a missed note, a wrong note or an octave error, the cursor must recover. Unit tests: every skip pattern,
  repeated notes, an empty expected sequence, n = 128, a new sequence set mid-run.
- **Real-time safety:** `test_rt_safety` with an expected sequence set; TSan for the handoff; the worst hop unchanged (the HMM runs on the
  worker, not the audio thread).

## What changes with the API (all in the implementation PR)

`intono.h` (9 functions), the ffigen bindings (CI checks freshness), the exported-symbol lists that CI pins (the `android` job in
`dsp.yml`, the shim's `exports.map` and the APK check in `flutter-app.yml`, the iOS link table and the XCTest list), the C API section of
`docs/architecture.md`, and `golden.py` (unchanged output in free mode is the check).

## Gate (pre-registered)

`docs/adr/sealed-p3gate-preregistration.md`: seeds 34201 to 34216, recall >= 0.995 on notes of 100 to 250 ms with a smaller adjacent
centre step of 100 to 150 cents in scale mode, with the sr1 gates as non-regression in the same run.

## Questions for Kelechi

1. **Hallucination as a sealed gate too?** The p3gate set plays exactly the expected notes, so it cannot show a false expected note.
   Proposal: a second registered set with 10 % deviations, gate "expected-note false positives <= free-mode extra notes", registered
   before the sealed run. Or keep it a dev check only.
2. **One skip in the cursor** (missed note) is enough for scales; more (e.g. two missed notes in a row) risks locking onto the wrong place
   in a scale that repeats pitch classes. Keep one?
