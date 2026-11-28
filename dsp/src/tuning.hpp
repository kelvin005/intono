// Tuning systems and cents maths (architecture doc: "Cents calculation", "Tuning systems").
#pragma once
#include <cmath>

namespace intono {

enum class Tuning : int { Equal = 0, Just = 1, Pythagorean = 2 };

inline double midi_to_hz(double midi, double a4) { return a4 * std::exp2((midi - 69.0) / 12.0); }
inline double cents_between(double f_measured, double f_target) { return 1200.0 * std::log2(f_measured / f_target); }

struct Target {
  double hz = 0.0;
  int midi_note = 0;  // ET note number nearest to the target, for display
  double cents = 0.0; // measured vs target
};

// Scale ratios above the tonic, one octave.
inline constexpr double kJust[12] = {1.0, 16.0 / 15, 9.0 / 8, 6.0 / 5, 5.0 / 4, 4.0 / 3,
                                     45.0 / 32, 3.0 / 2, 8.0 / 5, 5.0 / 3, 9.0 / 5, 15.0 / 8};
inline constexpr double kPythag[12] = {1.0, 256.0 / 243, 9.0 / 8, 32.0 / 27, 81.0 / 64, 4.0 / 3,
                                       729.0 / 512, 3.0 / 2, 128.0 / 81, 27.0 / 16, 16.0 / 9, 243.0 / 128};

// Nearest target for a measured pitch. Allocation-free, O(12).
inline Target nearest_target(double hz, Tuning t, double a4, int tonic_midi) {
  Target out;
  if (!(hz > 0.0)) return out;
  if (t == Tuning::Equal) {
    const int m = static_cast<int>(std::lround(69.0 + 12.0 * std::log2(hz / a4)));
    out.midi_note = m;
    out.hz = midi_to_hz(m, a4);
    out.cents = cents_between(hz, out.hz);
    return out;
  }
  const double* ratios = (t == Tuning::Just) ? kJust : kPythag;
  const double f_tonic = midi_to_hz(tonic_midi, a4);
  const int oct0 = static_cast<int>(std::floor(std::log2(hz / f_tonic)));
  double best = 1e30;
  for (int o = oct0 - 1; o <= oct0 + 1; ++o) {
    for (int k = 0; k < 12; ++k) {
      const double f = f_tonic * ratios[k] * std::exp2(o);
      const double c = cents_between(hz, f);
      if (std::fabs(c) < std::fabs(best)) {
        best = c;
        out.hz = f;
        out.cents = c;
      }
    }
  }
  out.midi_note = static_cast<int>(std::lround(69.0 + 12.0 * std::log2(out.hz / a4)));
  return out;
}

// The target of a given ET note number (the tuning's own pitch for that note), or hz == 0 if the tuning has none for it. Used in scale
// mode, where the expected note is known (ADR 0018).
inline Target target_for_midi(double hz, Tuning t, double a4, int tonic_midi, int midi) {
  Target out;
  if (!(hz > 0.0)) return out;
  if (t == Tuning::Equal) {
    out.midi_note = midi;
    out.hz = midi_to_hz(midi, a4);
    out.cents = cents_between(hz, out.hz);
    return out;
  }
  const double* ratios = (t == Tuning::Just) ? kJust : kPythag;
  const double f_tonic = midi_to_hz(tonic_midi, a4);
  const int oct0 = static_cast<int>(std::floor(std::log2(hz / f_tonic)));
  double best = 1e30;
  for (int o = oct0 - 2; o <= oct0 + 2; ++o)
    for (int k = 0; k < 12; ++k) {
      const double f = f_tonic * ratios[k] * std::exp2(o);
      if (static_cast<int>(std::lround(69.0 + 12.0 * std::log2(f / a4))) != midi) continue;
      const double c = cents_between(hz, f);
      if (std::fabs(c) < std::fabs(best)) {
        best = c;
        out.hz = f;
        out.cents = c;
      }
    }
  out.midi_note = midi;
  return out;
}

}  // namespace intono
