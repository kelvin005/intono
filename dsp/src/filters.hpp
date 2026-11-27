// Preprocess filters: DC blocker, 2nd-order Butterworth biquads. Double precision state
// so the C++ core matches the scipy reference (tools/accuracy/ref/yin_ref.py).
#pragma once
#include <cmath>

namespace intono {

// Denormal guard (ADR 0008, Amendment 1). A decaying tail (digital silence after a note) makes the filter states and then the
// float window pass through the denormal range, where x86 and ARM arithmetic is 10 to 100 times slower: hops of 130 to 300 us
// instead of 14 us. A software flush is portable and deterministic across platforms (no MXCSR/FPCR, no change to the caller's
// floating-point environment). It is exact for every value above the threshold, so it changes nothing but signals below -360 dBFS.
//
// INTONO_DENORMAL_GUARD (CMake option, default ON, ADR 0009 answer 4) exists only so bench mode can compare a guard-free build on the
// phone, as information. The default build is bit-identical to phase1-complete; CI proves it. Never ship the OFF build.
#ifndef INTONO_DENORMAL_GUARD
#define INTONO_DENORMAL_GUARD 1
#endif
#if INTONO_DENORMAL_GUARD
inline double flush_state(double v) { return (v > -1e-30 && v < 1e-30) ? 0.0 : v; }
inline float flush_sample(float v) { return (v > -1e-18f && v < 1e-18f) ? 0.f : v; }   // squares stay above FLT_MIN (1.2e-38)
#else
inline double flush_state(double v) { return v; }
inline float flush_sample(float v) { return v; }
#endif

// y[n] = x[n] - x[n-1] + R*y[n-1]
struct DcBlocker {
  double r = 0.995, x1 = 0.0, y1 = 0.0;
  double process(double x) {
    const double y = x - x1 + r * y1;
    x1 = flush_state(x);
    y1 = flush_state(y);
    return y;
  }
  void reset() { x1 = y1 = 0.0; }
};

// Direct form II transposed. Bilinear-transform design with Q = 1/sqrt(2) is exactly
// the 2nd-order Butterworth that scipy.signal.butter(2, fc, fs=sr) returns.
struct Biquad {
  double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0, z1 = 0, z2 = 0;

  static Biquad butter2(bool highpass, double fc, double fs) {
    const double pi = 3.14159265358979323846;
    const double k = std::tan(pi * fc / fs);
    const double q = 0.70710678118654752440;
    const double norm = 1.0 / (1.0 + k / q + k * k);
    Biquad f;
    if (highpass) {
      f.b0 = norm;
      f.b1 = -2.0 * norm;
      f.b2 = norm;
    } else {
      f.b0 = k * k * norm;
      f.b1 = 2.0 * f.b0;
      f.b2 = f.b0;
    }
    f.a1 = 2.0 * (k * k - 1.0) * norm;
    f.a2 = (1.0 - k / q + k * k) * norm;
    return f;
  }
  double process(double x) {
    const double y = b0 * x + z1;
    z1 = flush_state(b1 * x - a1 * y + z2);
    z2 = flush_state(b2 * x - a2 * y);
    return y;
  }
  void reset() { z1 = z2 = 0.0; }
};

}  // namespace intono
