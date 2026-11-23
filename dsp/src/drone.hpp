// Additive drone synthesiser. set() is called from the UI thread, render() from the audio
// thread; parameters cross threads through relaxed atomics only. No allocation, no locks.
#pragma once
#include <atomic>
#include <cmath>

#include "tuning.hpp"

namespace intono {

class Drone {
 public:
  Drone(double sample_rate, double a4) : sr_(sample_rate), a4_(a4) {}

  void set(int midi_note, float gain, int timbre) {
    note_.store(midi_note, std::memory_order_relaxed);
    gain_.store(gain < 0.f ? 0.f : (gain > 1.f ? 1.f : gain), std::memory_order_relaxed);
    timbre_.store(timbre, std::memory_order_relaxed);
  }

  // Writes n samples (overwrites `out`).
  void render(float* out, int n) {
    const int note = note_.load(std::memory_order_relaxed);
    const float target = gain_.load(std::memory_order_relaxed);
    const int timbre = timbre_.load(std::memory_order_relaxed);
    const double f0 = midi_to_hz(note, a4_);
    const double inc = f0 / sr_;
    int harmonics = timbre == 0 ? 1 : kRichHarmonics;
    while (harmonics > 1 && f0 * harmonics > 0.45 * sr_) --harmonics;  // stay below Nyquist
    // normalise so the rich timbre peaks near the same level as the sine
    double norm = 0.0;
    for (int k = 1; k <= harmonics; ++k) norm += 1.0 / k;
    const double scale = 1.0 / norm;
    for (int i = 0; i < n; ++i) {
      gain_state_ += (target - gain_state_) * 0.002f;  // ~10 ms smoothing, avoids clicks
      double s = 0.0;
      for (int k = 1; k <= harmonics; ++k) s += std::sin(kTwoPi * k * phase_) / k;
      out[i] = static_cast<float>(gain_state_ * s * scale);
      phase_ += inc;
      if (phase_ >= 1.0) phase_ -= std::floor(phase_);
    }
  }

 private:
  static constexpr int kRichHarmonics = 8;
  static constexpr double kTwoPi = 6.283185307179586476925286766559;
  double sr_, a4_;
  std::atomic<int> note_{69};
  std::atomic<float> gain_{0.f};
  std::atomic<int> timbre_{0};
  double phase_ = 0.0;
  float gain_state_ = 0.f;
};

}  // namespace intono
