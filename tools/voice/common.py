"""Shared helpers for the ADR 0006 voice-rejection tools. Test tooling only: no audio is committed, shipped or uploaded."""
import hashlib
import json
import os
import subprocess
import tempfile
from math import gcd

import numpy as np
import soundfile as sf
from scipy import signal

SALT = "intono-voice-1"          # ADR 0006, "Splits": pool = sha256(SALT:id) rank, lowest 25 % sealed
SEALED_FRACTION = 0.25
ENGINE_SR = 48000
WIN, HOP = 1024, 256             # engine config (intono_config: window_size, hop_size)
HP_HZ, LP_HZ = 150.0, 4000.0     # engine.cpp kHighpassHz / kLowpassHz
BAND_HZ = 5000.0                 # ADR 0006: features use only the band below 5 kHz (all corpora are 16 kHz)
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DEFAULT_PUBLIC = os.path.join(ROOT, "testdata", "public")
FROZEN_CLI = "/tmp/frozen/intono-cli-gate4"   # dsp-v0.1-synthetic + ADR 0004 Amendment 4 (the base of every ADR 0006 gate)


def sha256_file(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def rank_key(item_id):
    return hashlib.sha256(f"{SALT}:{item_id}".encode()).hexdigest()


def load_audio(path):
    x, sr = sf.read(path, dtype="float32", always_2d=True)
    return x.mean(axis=1).astype(np.float32), int(sr)


def resample(x, sr_in, sr_out):
    if sr_in == sr_out:
        return x.astype(np.float32)
    g = gcd(int(sr_in), int(sr_out))
    return signal.resample_poly(x, sr_out // g, sr_in // g).astype(np.float32)


def write_wav(path, x, sr):
    sf.write(path, np.asarray(x, dtype=np.float32), int(sr), subtype="FLOAT")


def rms_db(x):
    return 20.0 * np.log10(np.sqrt(np.mean(np.square(x, dtype=np.float64)) + 1e-20) + 1e-12)


def scale_to_db(x, target_db):
    return (x * 10.0 ** ((target_db - rms_db(x)) / 20.0)).astype(np.float32)


def write_json(path, obj):
    with open(path, "w") as f:
        json.dump(obj, f, indent=1, sort_keys=True)


def read_json(path):
    with open(path) as f:
        return json.load(f)


def run_cli(cli, wav, notes=False, extra=()):
    """Run intono-cli on a WAV; returns frames (n, 9) or notes (m, 10) as float arrays."""
    args = [cli, wav] + (["--notes", "1"] if notes else []) + list(extra)
    out = subprocess.run(args, capture_output=True, text=True, check=True).stdout
    rows = [r for r in out.splitlines() if r and not r[0].isalpha()]
    if not rows:
        return np.zeros((0, 10 if notes else 9))
    return np.array([[float(v) for v in r.split(",")] for r in rows])


FRAME_COLS = ["t", "hz", "conf", "midi", "cents", "vib_rate", "vib_width", "voiced", "onset"]
NOTE_COLS = ["t_start", "t_end", "midi", "mean_cents", "std_cents", "vib_rate", "vib_width", "mean_conf", "frames", "emit_t"]


def hop_centre_times(n_samples, sr):
    n_hops = max(0, (n_samples - WIN) // HOP + 1)
    return (np.arange(n_hops) * HOP + WIN / 2.0) / sr


def engine_filter(x, sr):
    """Causal copy of the engine's front end (2nd-order Butterworth high-pass 150 Hz and low-pass 4 kHz)."""
    sos = np.vstack([signal.butter(2, HP_HZ, "highpass", fs=sr, output="sos"), signal.butter(2, LP_HZ, "lowpass", fs=sr, output="sos")])
    return signal.sosfilt(sos, x).astype(np.float32)


def align_lag(ref, test, max_lag=4096):
    """Lag (samples) at which `test` best matches `ref` (codec delay compensation)."""
    n = min(len(ref), len(test), 48000 * 3)
    c = signal.correlate(test[: n + max_lag], ref[:n], mode="valid", method="fft")
    return int(np.argmax(c))
