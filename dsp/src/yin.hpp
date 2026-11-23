// YIN pitch detector (de Cheveigne & Kawahara 2002), FFT-accelerated with pffft.
// Window/hop/range/threshold come from intono_config; the core is sample-rate agnostic.
// All memory is allocated in the constructor; analyze() never allocates.
#pragma once
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <vector>

#include "pffft.h"

namespace intono {

struct YinResult {
  double hz = 0.0;       // sub-sample refined estimate, 0 if none
  double confidence = 0; // 1 - normalised difference at the chosen lag
  bool found = false;    // true when a lag fell below the threshold
};

class Yin {
 public:
  Yin(double sample_rate, int window, double min_hz, double max_hz, double threshold)
      : sr_(sample_rate), win_(window), thr_(threshold) {
    tau_min_ = std::max(2, static_cast<int>(std::floor(sr_ / max_hz)));
    tau_max_ = static_cast<int>(std::ceil(sr_ / min_hz));
    w_ = win_ - tau_max_ - 1;  // integration window; lags up to tau_max+1 are needed
    if (w_ <= tau_max_) return;  // invalid: window too short for min_hz
    nfft_ = pffft_next_power_of_two(win_ + w_);
    setup_ = pffft_new_setup(nfft_, PFFFT_REAL);
    if (!setup_) return;
    fx_ = alloc(nfft_); fw_ = alloc(nfft_); FX_ = alloc(nfft_); FW_ = alloc(nfft_);
    FR_ = alloc(nfft_); work_ = alloc(nfft_);
    sq_.assign(static_cast<size_t>(win_) + 1, 0.0);
    dn_.assign(static_cast<size_t>(tau_max_) + 2, 1.0);
    ok_ = true;
  }
  ~Yin() {
    for (float* p : {fx_, fw_, FX_, FW_, FR_, work_}) if (p) pffft_aligned_free(p);
    if (setup_) pffft_destroy_setup(setup_);
  }
  Yin(const Yin&) = delete;
  Yin& operator=(const Yin&) = delete;

  bool ok() const { return ok_; }
  int tau_min() const { return tau_min_; }
  int tau_max() const { return tau_max_; }

  // frame: win samples. Not thread-safe; call from one thread only.
  YinResult analyze(const float* x) {
    // cumulative energy
    for (int i = 0; i < win_; ++i) sq_[i + 1] = sq_[i] + static_cast<double>(x[i]) * x[i];
    const double e0 = sq_[w_] - sq_[0];
    if (e0 < 1e-12) {  // digital silence: every lag "matches"; there is no pitch. Checked BEFORE the FFT (ADR 0008, Amendment 1): the
      YinResult none;  // spectrum products of a 1e-17 decay tail are denormal floats, 100 us instead of 8; the result is the same as before.
      none.confidence = 0.0;
      return none;
    }
    // r(tau) = sum_{j<W} x_j x_{j+tau} as a convolution with the reversed head segment
    std::fill(fx_, fx_ + nfft_, 0.f);
    std::fill(fw_, fw_ + nfft_, 0.f);
    std::copy(x, x + win_, fx_);
    for (int j = 0; j < w_; ++j) fw_[w_ - 1 - j] = x[j];
    pffft_transform(setup_, fx_, FX_, work_, PFFFT_FORWARD);
    pffft_transform(setup_, fw_, FW_, work_, PFFFT_FORWARD);
    pffft_zconvolve_scale(setup_, FX_, FW_, FR_, 1.0f / static_cast<float>(nfft_));
    pffft_transform(setup_, FR_, fx_, work_, PFFFT_BACKWARD);  // fx_ now holds the convolution

    const int n = tau_max_ + 2;
    double cum = 0.0;
    dn_[0] = 1.0;
    for (int tau = 1; tau < n; ++tau) {
      const double etau = sq_[tau + w_] - sq_[tau];
      double d = e0 + etau - 2.0 * static_cast<double>(fx_[tau + w_ - 1]);
      if (d < 0.0) d = 0.0;
      cum += d;
      dn_[tau] = d * tau / std::max(cum, 1e-20);
    }

    YinResult out;
    int k = -1;
    for (int tau = tau_min_; tau <= tau_max_; ++tau) {
      if (dn_[tau] < thr_) {
        k = tau;
        while (k + 1 <= tau_max_ && dn_[k + 1] < dn_[k]) ++k;  // walk down to the local minimum
        // A minimum sitting on the edge of the search range is a boundary artefact (typically a
        // partial window at a note attack reporting max_hz), not a real period.
        out.found = (k > tau_min_ && k < tau_max_);
        break;
      }
    }
    if (k < 0) {  // no candidate under the threshold: global minimum, flagged unvoiced
      k = tau_min_;
      for (int tau = tau_min_ + 1; tau <= tau_max_; ++tau) if (dn_[tau] < dn_[k]) k = tau;
    }
    double off = 0.0;
    if (k >= 1 && k < n - 1) {
      const double a = dn_[k - 1], b = dn_[k], c = dn_[k + 1];
      const double den = a - 2.0 * b + c;
      if (std::fabs(den) > 1e-12) off = std::clamp(0.5 * (a - c) / den, -1.0, 1.0);
    }
    const double lag = k + off;
    out.hz = lag > 0.0 ? sr_ / lag : 0.0;
    out.confidence = std::clamp(1.0 - dn_[k], 0.0, 1.0);
    return out;
  }

 private:
  static float* alloc(int n) { return static_cast<float*>(pffft_aligned_malloc(sizeof(float) * n)); }

  double sr_;
  int win_;
  double thr_;
  int tau_min_ = 0, tau_max_ = 0, w_ = 0, nfft_ = 0;
  PFFFT_Setup* setup_ = nullptr;
  float *fx_ = nullptr, *fw_ = nullptr, *FX_ = nullptr, *FW_ = nullptr, *FR_ = nullptr, *work_ = nullptr;
  std::vector<double> sq_, dn_;
  bool ok_ = false;
};

}  // namespace intono
