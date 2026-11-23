# Phase 1 accuracy report (libintono, C++)

Synthetic set: 136 clips, scored through `intono-cli` with the Phase 0 metrics. Real recordings (URMP, NSynth) not yet run.

## Gate targets

| Metric | Target | Result | |
|---|---|---|---|
| gross_error_pct | < 1.0 | 0.000 | PASS |
| cents_mae_centre_stable | < 3.0 | 0.637 | PASS |
| cents_mae_centre_vibrato | < 5.0 | 0.647 | PASS |
| us_per_hop | < 1000.0 | 14.250 | PASS |

## Regression against Phase 0 (allowed: +0.5 pp / +0.5 c)

| Metric | Phase 0 (Python) | Phase 1 (C++) | |
|---|---|---|---|
| gross_error_pct | 0.000 | 0.000 | PASS |
| octave_error_pct | 0.000 | 0.000 | PASS |
| cents_mae_centre_stable | 0.637 | 0.637 | PASS |
| cents_mae_centre_vibrato | 0.647 | 0.647 | PASS |
| voicing_false_alarm_pct | 0.000 | 0.000 | PASS |

## Other metrics

- Raw pitch accuracy (±50¢, displayed pitch): 100.00%
- Octave error: 0.000%   Voicing recall: 100.00%   False alarm in silence: 0.000%
- Cents MAE per frame (displayed, stable): 0.640   p95: 2.660
- Onset on note start: precision 1.000, recall 1.000, F1 1.000
- CPU: 14.2 µs per 5.33 ms hop (0.27% of one core, this machine)

## Parity with the Python reference (frame by frame)

- 42840 frames compared, voiced mismatches: 0
- Displayed pitch difference: median 0.00007 c, p99 0.00043 c, max 0.00117 c

## Note level (ADR 0003): labelled synthetic phrases, 8 notes each, separated and legato, ±40 c detuning, 40% vibrato, clean / 20 dB / 10 dB SNR

| Gate | Target | Result | |
|---|---|---|---|
| note_precision | >= 0.98 | 1.000 | PASS |
| note_recall | >= 0.98 | 1.000 | PASS |
| note_cents_mae | < 3.0 | 0.104 | PASS |

- 576 true notes, 576 reported; notes with the right ET number but start >50 ms off count as misses; wrong-number notes at the right time: 0
- Cents error of the whole-note mean vs the intended detuning: steady notes MAE 0.104, p95 0.331; vibrato notes MAE 0.940 (whole-note mean of the raw pitch, partial cycles included)
- Timing: start MAE 8.9 ms, end MAE 11.1 ms

| Phrase set | Precision | Recall | Wrong # | Steady MAE ¢ | Vib MAE ¢ |
|---|---|---|---|---|---|
| dev | 1.000 | 1.000 | 0 | 0.130 | 0.888 |
| heldout_77 | 1.000 | 1.000 | 0 | 0.108 | 0.923 |
| heldout_123 | 1.000 | 1.000 | 0 | 0.080 | 1.094 |
| heldout_2024 | 1.000 | 1.000 | 0 | 0.099 | 0.866 |

Parity with the Python mirror on the dev set (18 phrases): note count mismatches 0, note value mismatches 0, onset-flag mismatch frames 0, max mean/std difference 0.0005 c, max time difference 0.00000 s

## By condition

| Condition | Gross % | Centre MAE ¢ | Vib-centre MAE ¢ | FA % |
|---|---|---|---|---|
| sine | 0.00 | 0.53 | nan | 0.00 |
| saw | 0.00 | 0.52 | nan | 0.00 |
| violin | 0.00 | 0.50 | nan | 0.00 |
| violin_vib | 0.00 | nan | 0.55 | 0.00 |
| violin_snr30 | 0.00 | 0.44 | nan | 0.00 |
| violin_snr20 | 0.00 | 0.65 | nan | 0.00 |
| violin_snr10 | 0.00 | 1.19 | nan | 0.00 |
| violin_vib_snr20 | 0.00 | nan | 0.74 | 0.00 |
