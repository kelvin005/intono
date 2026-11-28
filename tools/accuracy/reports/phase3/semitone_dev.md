# Semitone set (60 to 80 cent steps), dev seeds only: why it is not registered yet

Generator: `ref/semitone_set.py`. Runner: `run_semitones.py`, dev seeds 9561 to 9576. Binary: the frozen `fc29130`, the same DSP as
`main`. The sealed seeds 34501 to 34516 (sha256 of the list 408e17b3…f1e6b2) have not been generated or run.

| Mode | Notes | Recall (gate ≥ 0.99) | Invented (gate ≤ 0.5 %) | Recall, 100 to 250 ms notes |
|---|---|---|---|---|
| Scale | 2846 | **0.891** | **1.93 %** (55) | 0.863 |
| Free | 2846 | 0.455 | 10.4 % (296) | 0.340 |

Scale mode, by how far off its semitone the note is:

| \|detune\| | No vibrato | Vibrato |
|---|---|---|
| 0 to 20 cents | 0.930 (913 notes) | 0.917 (969) |
| 20 to 30 cents | 0.969 (286) | 0.912 (262) |
| 30 to 40 cents | 0.641 (206) | 0.714 (210) |

Invented notes:
- 38 are the neighbouring semitone of the note being played;
- 17 are the right note, with its onset more than 80 ms off (a split or a late start).

**Reading.** When every step is only 60 to 80 cents, neighbouring notes overlap the note HMM's semitone states, which are 100 cents
apart with a ±50 cent tolerance. The decoder merges them or labels one as its neighbour, even with the scale's bias (ADR 0014).
- The earlier dev figure of 0.996 (ADR 0004, Amendment 5) was for an **isolated** 60 to 80 cent step inside ordinary runs.
- This set makes **every** step narrow, with notes up to 40 cents off.
- Passing ≥ 0.99 here needs a change to the scale-mode decoder, which is a DSP change under the freeze.
