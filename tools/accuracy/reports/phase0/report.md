# Phase 0 baseline report

Synthetic set: 136 clips (G3–E7, sine/saw/violin-like, detune ±1–50¢, vibrato 4–8 Hz 10–80¢, pink noise 30/20/10 dB). URMP/NSynth not yet run.

| Metric | Target | yin | pyin |
|---|---|---|---|
| Raw pitch accuracy (±50¢) % |  | 100.00 | 100.00 |
| Gross pitch error % | < 1 | 0.00 | 0.00 |
| Octave error % |  | 0.00 | 0.00 |
| Voicing recall on notes % |  | 100.00 | 100.00 |
| Voicing false alarm (silence) % |  | 0.00 | 2.73 |
| Cents MAE, per frame (raw) |  | 0.69 | 2.06 |
| Cents MAE, displayed centre, stable | < 3 (Phase 0 gate < 5) | 0.64 | 2.01 |
| Cents MAE, vibrato centre | < 5 | 0.65 | 1.02 |
| Python ms per hop (not the C++ budget) |  | 0.08 | 5.10 |
| **Phase 0 gate (MAE < 5¢)** |  | PASS | PASS |

## yin by condition

| Condition | RPA % | Gross % | Octave % | Centre MAE ¢ | Vib-centre MAE ¢ | FA % |
|---|---|---|---|---|---|---|
| sine | 100.0 | 0.00 | 0.00 | 0.53 | nan | 0.00 |
| saw | 100.0 | 0.00 | 0.00 | 0.52 | nan | 0.00 |
| violin | 100.0 | 0.00 | 0.00 | 0.50 | nan | 0.00 |
| violin_vib | 100.0 | 0.00 | 0.00 | nan | 0.55 | 0.00 |
| violin_snr30 | 100.0 | 0.00 | 0.00 | 0.44 | nan | 0.00 |
| violin_snr20 | 100.0 | 0.00 | 0.00 | 0.65 | nan | 0.00 |
| violin_snr10 | 100.0 | 0.00 | 0.00 | 1.19 | nan | 0.00 |
| violin_vib_snr20 | 100.0 | 0.00 | 0.00 | nan | 0.74 | 0.00 |

Worst clips by gross error: m55_sine (0/195), m55_saw (0/195), m55_violin (0/195), m55_violin_vib (0/195), m55_violin_snr30 (0/195)

## pyin by condition

| Condition | RPA % | Gross % | Octave % | Centre MAE ¢ | Vib-centre MAE ¢ | FA % |
|---|---|---|---|---|---|---|
| sine | 100.0 | 0.00 | 0.00 | 4.56 | nan | 3.57 |
| saw | 100.0 | 0.00 | 0.00 | 1.75 | nan | 3.87 |
| violin | 100.0 | 0.00 | 0.00 | 1.47 | nan | 2.01 |
| violin_vib | 100.0 | 0.00 | 0.00 | nan | 0.95 | 0.82 |
| violin_snr30 | 100.0 | 0.00 | 0.00 | 1.17 | nan | 1.86 |
| violin_snr20 | 100.0 | 0.00 | 0.00 | 1.37 | nan | 2.31 |
| violin_snr10 | 100.0 | 0.00 | 0.00 | 1.73 | nan | 2.76 |
| violin_vib_snr20 | 100.0 | 0.00 | 0.00 | nan | 1.10 | 4.62 |

Worst clips by gross error: m55_sine (0/195), m55_saw (0/195), m55_violin (0/195), m55_violin_vib (0/195), m55_violin_snr30 (0/195)
