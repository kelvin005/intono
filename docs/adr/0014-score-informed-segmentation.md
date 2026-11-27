# ADR 0014: Score-informed segmentation in scale mode (the hard Phase 3 gate)

Status: **Accepted** (Kelechi, 2026-11-27; answers below). Both sealed sets (p3gate: recall; p3dev: invented notes) are pre-registered
in `docs/adr/sealed-p3gate-preregistration.md` before any of this exists. DSP change (in response to the recorded known limit, ADR 0004)
and C API change: the implementation PR needs Kelechi's "merge".

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
2. **Cursor, with a fallback** (Kelechi, 2026-11-27). The worker keeps `k`, the index of the expected note due next. When a note is
   emitted with `midi == expected[k]`, `k` advances by one; with `midi == expected[k+1]` (**at most one** missed note), by two. Any
   other note is a miss of the window. **After 3 consecutive notes that miss the window, the score bias is dropped** (plain, free-mode
   decoding) **until 2 consecutive notes match consecutive expected positions again** (`expected[p]`, `expected[p+1]` for some `p >= k`);
   then `k = p + 2` and the bias returns. So a player who loses their place, or plays something else, gets plain segmentation, never a
   score pulling the decoder towards notes they are not playing. Unit tests: every transition of that state machine (match, one skip,
   two skips, three misses, the re-sync, a re-sync attempt that matches only once).
3. **The only change to decoding:** while the bias is on, the cost of switching from the state of `expected[k-1]` (the note being
   played) into the state of `expected[k]` (the note due) is `kHmmSwitchExpected` instead of `kHmmSwitch` (24). Emission, tolerance, sigma, the fixed lag, the change-point fit and the glitch rule
   are unchanged. **One new parameter**, chosen on dev seeds 9501 to 9516 only, never on the sealed set.
4. **Free mode is unchanged byte for byte:** with no expected sequence the decoder runs exactly as today (`bit-identity-vs-phase1`, the
   golden manifest, G7).
5. **Note delay unchanged** (same lag), so the 350 ms note-delay gate is unaffected.
6. **CLI:** `intono-cli file.wav --notes 1 --expected 62,64,66,...` for the runner. The runner's scale mode passes each phrase's truth
   sequence, and the p3gate set is run once as registered.

## Risks and the checks for them

- **Inventing the expected note** when the player plays something else: now a **sealed gate** (p3dev, below), as hard as the recall
  gate. Dev seeds 9521 to 9536 first.
- **Losing the place:** the fallback above, with its unit tests.
- **Real-time safety:** `test_rt_safety` with an expected sequence set; TSan for the handoff; the worst hop unchanged (the HMM runs on
  the worker, not the audio thread).

## What changes with the API (all in the implementation PR)

`intono.h` (9 functions), the ffigen bindings (CI checks freshness), the exported-symbol lists that CI pins (the `android` job in
`dsp.yml`, the shim's `exports.map` and the APK check in `flutter-app.yml`, the iOS link table and the XCTest list), the C API section of
`docs/architecture.md`, and `golden.py` (unchanged output in free mode is the check).

## Gates (pre-registered, `docs/adr/sealed-p3gate-preregistration.md`)

| Set | Gate |
|---|---|
| **p3gate** (seeds 34201 to 34216) | recall >= 0.995 on notes of 100 to 250 ms with a smaller adjacent centre step of 100 to 150 cents, scale mode; the sr1 gates as non-regression |
| **p3dev** (seeds 34301 to 34316, 1024 deviations) | invented-expected-note rate **<= 0.5 %**; recall of the played deviation notes **>= 0.98** |
| free mode | byte-identical to today (bit-identity job, golden manifest) |

Parameters are chosen on dev seeds only: 9501 to 9516 (short runs) and 9521 to 9536 (deviations).

## Answers (Kelechi, 2026-11-27)

1. **Invented expected notes get their own sealed gate:** a pre-registered set with about 10 % deviations (wrong, skipped, repeated,
   off-scale notes); invented-expected-note rate <= 0.5 % of deviation notes and recall of the played deviation notes >= 0.98. A false
   note is worse than a missed one, so this gate is as hard as the recall gate.
2. **Skip at most one missed note, plus the fallback:** after 3 consecutive notes outside the expected window, plain segmentation until
   2 consecutive notes match an expected position again. The fallback is tested.

## Amendment 1 (proposed 2026-11-27, implementation PR; needs Kelechi's "merge"): cheap entry into the due note, from any state

**What the dev seeds showed.** Decision 3 as accepted (a cheap switch *from* `expected[k-1]` *into* `expected[k]`) failed the deviation
gates on dev seeds 9521 to 9536 at the first cost tried (8): 8 invented notes in 1024 (0.78 %, limit 0.5 %), recall of the played
deviation notes 0.978 (limit 0.98). All 8 were off-scale insertions: the player puts a note X before the due note E[p]. Decoding
E[p-1] -> X -> E[p] costs two full switches (48), decoding E[p-1] -> E[p] one cheap one, so an X within a semitone of E[p] was absorbed
into an E[p] that starts early (the scoring counts that as inventing E[p]). Raising the cost trades one gate for the other, and no value
passes both with margin:

| Cost (step rule) | G-P3 band recall (1043 notes) | invented (of 1024) | deviation recall |
|---|---|---|---|
| 8 | 0.9981 | 8 | 0.9779 |
| 12 | 0.9952 | 3 | 0.9909 |
| 16 | 0.9923 | 2 | 0.9948 |
| 20 | 0.9837 | 0 | 0.9974 |

**The change.** Decision 3 becomes: while the bias is on, **entering the state of a note due next** (`expected[k]`, or `expected[k+1]`
for the one allowed skip; the targets of the cursor's window) costs `kHmmSwitchExpected` **from whatever state the best path is in**,
instead of only from the state of `expected[k-1]`. An inserted note then costs what it costs in free mode (one full switch in, one cheap
switch out), so the bias no longer pays for swallowing it. Everything else in decision 3 is unchanged: emission, tolerance, sigma, the
fixed lag, the change-point fit and the glitch rule; one parameter; free mode byte-identical. The cursor (decision 2) is unchanged.

| Cost (entry rule) | G-P3 band recall | invented | deviation recall | extra notes per 200 |
|---|---|---|---|---|
| 4, 6, 8 (identical) | **0.9981** (2 misses) | **0** | **0.9987** | 0.14 |
| 12 | 0.9952 | 0 | 0.9987 | 0.07 |
| 16 | 0.9847 | 0 | 0.9987 | 0.35 |

**Chosen: `kHmmSwitchExpected` = 8**, the weakest bias on the plateau where 4, 6 and 8 give identical results (dev seeds only). The two
remaining misses are 100 and 111 ms notes at a 100 and 101 cent step, the corner of the gated band. Unit test
`ScaleMode.AnOffScaleNoteInsertedBeforeTheDueNoteIsReportedAsPlayed` fails with the step rule and passes with the entry rule.
Report: `tools/accuracy/reports/phase3/score_informed_dev.md`.
