# Narrow-step sets, dev seeds 9561 to 9576 (ADR 0018)

Generators: `ref/semitone_set.py` (`build_realistic_set` = (a), `build_semitone_set` = (b)). Runner: `run_semitones.py --set realistic|stress`.
Scale mode (the phrase's MIDI sequence is the expected sequence). Dev seeds only; the sealed seeds (34601 to 34616, 34501 to 34516) are not
generated or run (`docs/adr/sealed-p3semi-preregistration.md`).

| Set | Binary | Notes | Recall | Invented | Recall, 100 to 250 ms |
|---|---|---|---|---|---|
| (a) realistic | `main` before ADR 0018 (frozen `fc29130`) | 3333 | 0.9955 | 0.33 % (11) | 0.9941 |
| (a) realistic | ADR 0018 (tolerance 30, label window 60) | 3333 | **0.9979** | **0.15 %** (5) | 0.9975 |
| (b) stress | `main` before ADR 0018 | 2846 | 0.891 | 1.93 % (55) | 0.863 |
| (b) stress | ADR 0018 | 2846 | **0.9817** | 0.56 % (16) | 0.976 |
| (b) stress, free mode (no expected sequence), before | | 2846 | 0.455 | 10.4 % | 0.340 |

Why (b) failed before: the HMM's +-50 cent cost-free zone around each semitone overlaps its neighbour's for notes played 20 to 40 cents
off, so a note 13 cents outside the neighbouring zone cost 0.5 per frame, less than a switch (8). Scale-mode tolerance 30 and a 60 cent
label window against the due notes fix most of it. Sweeps and the non-regression runs (short runs 9501 to 9516: 1.0000; deviations
9521 to 9536: 0 invented, recall 1.0000; golden free mode 288 of 288 identical) are in ADR 0018.

Note: the first version of generator (a) let a scale run below G3, which is not a violin range; 3 of its 4 first-run misses were notes
below the instrument's range. Fixed before any parameter was chosen (the sweep numbers above are from the fixed generator).
