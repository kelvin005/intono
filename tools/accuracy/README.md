# tools/accuracy

Accuracy harness for the Intono DSP core. Phase 0 is the Python reference; Phase 1 adds a C++ CLI that is scored by the same metrics.

## Phase 0 (this folder: `ref/`)

| File | Purpose |
|---|---|
| `yin_ref.py` | Reference pipeline: DC blocker, HP 150 Hz, LP 4 kHz, noise gate, YIN (1024/256, 180-3200 Hz, threshold 0.12, parabolic), octave guard, vibrato-aware centre pitch |
| `synth.py` | Synthetic labelled set: 136 clips, G3-E7, sine/saw/violin-like, detune ±1-50 c, vibrato 4-8 Hz, pink noise 30/20/10 dB |
| `metrics.py` | RPA (mir_eval), gross and octave error, cents MAE (stable and vibrato centre), voicing false alarm |
| `run_baseline.py` | Runs plain YIN and librosa pYIN, writes `reports/phase0/report.{json,md}` |
| `fetch_datasets.py` | Prepares NSynth (download) and URMP (local folder) into wav + f0.csv pairs |

```
pip install numpy scipy librosa mir_eval soundfile
python ref/run_baseline.py --out reports/phase0
python ref/fetch_datasets.py nsynth          # needs network access to download.magenta.tensorflow.org
python ref/run_baseline.py --wav-dir data/prepared/nsynth --out reports/phase0_nsynth
```

## Phase 0 results (synthetic set only)

| Metric | Target | YIN (spec + ADR 0001) | pYIN (resolution 0.02) |
|---|---|---|---|
| Gross pitch error % | < 1 | 0.00 | 0.00 |
| Cents MAE, stable centre | < 3 (gate < 5) | 0.64 | 2.01 |
| Cents MAE, vibrato centre | < 5 | 0.65 | 1.02 |

URMP and NSynth have **not** been run yet (no network access in the build environment). The gate is provisionally met on synthetic audio only; it must be re-confirmed on real violin recordings.

pYIN note: librosa's default `resolution=0.1` means 10-cent bins and inflated its error to 3.5 c. `resolution=0.01` makes librosa 1.0.1 return no voiced frames, so the baseline uses 0.02.

## Vibrato centre (ADR 0001)

The doc's autocorrelation method on a 250 ms contour cannot see a 4 Hz vibrato (period 250 ms) and misses the target at 5.75 c. `docs/adr/0001-vibrato-centre-pitch.md` records the decision: peak/trough midpoints with an 8 c minimum swing, averaging over the last full cycle, a 250 ms hold-over, and a 150 ms median fallback. Result 0.65 c (1.03 c at 10 dB SNR), 0% false vibrato on non-vibrato clips. `centre_method` options in `yin_ref.py`: `extrema` (ADR), `extrema_v0` (no safeguards), `autocorr` (doc as written).

## Bit-identity against phase1-complete (ADR 0009 answer 4, Amendment 2)

`golden/phase1-complete.json` holds, for every case of the synthetic dev corpus (all phrase sets of seeds 21, 77, 123, 2024; each clip as
is and with 3 s of digital silence appended; frames and notes mode), the SHA-256 of the float32 input and of `intono-cli`'s output when
built from the `phase1-complete` tag. It was made with `golden.py make` on the tag's binary, which refuses to write it unless the inline
and threaded outputs agree, so one manifest checks both modes.

```
PYTHONDONTWRITEBYTECODE=1 python golden.py check --cli ../../build/intono-cli --golden golden/phase1-complete.json [--threaded] --jobs 32
INTONO_CLI=../../build/intono-cli python test_golden.py
```

`DIFF` is a real output change; run `diff_cli.py --a <tag build> --b <this build>` to see the first differing line. `INPUT DRIFT` means the
synthetic input changed (numpy/scipy versions: CI pins those in the manifest's `env`), which invalidates the comparison without
implicating the DSP. The `golden-provenance` job in `dsp.yml` rebuilds the tag and re-checks the manifest weekly, on manual runs, and
whenever the manifest, `golden.py` or `ref/synth.py` change. The manifest is never regenerated from anything but the tag.
