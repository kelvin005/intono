#pragma once
#include <cmath>
#include <vector>
#include <cstdint>
#include <cstdlib>

#include "engine_internal.hpp"

namespace testutil {

// ADR 0008: every engine test runs in inline mode (the certified path) by default and, with INTONO_TEST_THREADED=1, through the worker
// thread. `read_notes` waits for the worker first, so the same assertions hold in both modes.
inline bool threaded() { const char* v = std::getenv("INTONO_TEST_THREADED"); return v && *v && *v != '0'; }
inline intono_engine* make_engine(const intono_config* c) { return intono_internal::create(c, !threaded()); }
inline int read_notes(intono_engine* e, intono_note* out, int max) {
  intono_internal::drain(e);
  return intono_read_notes(e, out, max);
}

constexpr double kPi = 3.14159265358979323846;

inline std::vector<float> sine(double sr, double hz, double secs, double amp = 0.5) {
  std::vector<float> x(static_cast<size_t>(sr * secs));
  for (size_t i = 0; i < x.size(); ++i) x[i] = static_cast<float>(amp * std::sin(2 * kPi * hz * i / sr));
  return x;
}

// Harmonic tone with a weak fundamental (violin-like G string): the classic octave-error trap.
inline std::vector<float> harmonic(double sr, double f0, double secs, double fund_gain = 0.25, int nh = 12) {
  std::vector<float> x(static_cast<size_t>(sr * secs), 0.f);
  for (size_t i = 0; i < x.size(); ++i) {
    double s = 0;
    for (int k = 1; k <= nh && k * f0 < 0.45 * sr; ++k) s += (k == 1 ? fund_gain : 1.0) / std::pow(k, 0.7) * std::sin(2 * kPi * k * f0 * i / sr);
    x[i] = static_cast<float>(0.25 * s);
  }
  return x;
}

// Deterministic LCG noise in [-1, 1).
inline double noise(uint32_t& s) {
  s = s * 1664525u + 1013904223u;
  return (static_cast<double>(s >> 8) / 8388608.0) - 1.0;
}

}  // namespace testutil
