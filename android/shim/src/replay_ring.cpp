#include "replay_ring.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <thread>

namespace intono_shim {

namespace {
float* default_alloc(void*, size_t n) { return static_cast<float*>(std::calloc(n, sizeof(float))); }
void default_release(void*, float* p, size_t) { std::free(p); }

// Zeroes through a volatile pointer, so the stores cannot be removed as dead before the buffer is freed.
void secure_zero(float* p, size_t n) {
  volatile float* v = p;
  for (size_t i = 0; i < n; ++i) v[i] = 0.f;
}
}  // namespace

ReplayRing::ReplayRing() : ReplayRing(Allocator{nullptr, &default_alloc, &default_release}) {}

ReplayRing::ReplayRing(Allocator a) : alloc_(a) {
  if (!alloc_.alloc || !alloc_.release) alloc_ = Allocator{nullptr, &default_alloc, &default_release};
}

ReplayRing::~ReplayRing() { release(); }

void ReplayRing::wait_idle() const {
  while (in_busy_.load(std::memory_order_seq_cst) || out_busy_.load(std::memory_order_seq_cst)) std::this_thread::yield();
}

bool ReplayRing::arm(int sample_rate, double seconds) {
  release();
  if (sample_rate <= 0 || !(seconds > 0)) return false;
  const size_t n = static_cast<size_t>(std::llround(seconds * sample_rate));
  float* p = n ? alloc_.alloc(alloc_.ctx, n) : nullptr;
  if (!p) return false;
  cap_ = n;
  rate_ = sample_rate;
  fade_ = std::max(1, static_cast<int>(std::lround(0.005 * sample_rate)));
  start_.store(-1, std::memory_order_relaxed);
  end_.store(frames_.load(std::memory_order_acquire), std::memory_order_relaxed);
  frozen_.store(false, std::memory_order_relaxed);
  playing_.store(false, std::memory_order_relaxed);
  buf_.store(p, std::memory_order_seq_cst);
  recording_.store(true, std::memory_order_seq_cst);
  return true;
}

void ReplayRing::freeze() {
  if (!armed()) return;
  recording_.store(false, std::memory_order_seq_cst);
  frozen_.store(true, std::memory_order_seq_cst);
  // a block being written when recording stopped finishes before the UI reads the ring
  while (in_busy_.load(std::memory_order_seq_cst)) std::this_thread::yield();
}

void ReplayRing::release() {
  recording_.store(false, std::memory_order_seq_cst);
  playing_.store(false, std::memory_order_seq_cst);
  float* p = buf_.exchange(nullptr, std::memory_order_seq_cst);
  wait_idle();   // neither callback can still be inside the buffer: each sets its flag before it loads buf_
  frozen_.store(false, std::memory_order_seq_cst);
  start_.store(-1, std::memory_order_relaxed);
  if (!p) return;
  secure_zero(p, cap_);
  alloc_.release(alloc_.ctx, p, cap_);
  cap_ = 0;
}

int64_t ReplayRing::first_frame() const {
  const int64_t s = start_.load(std::memory_order_acquire);
  const int64_t e = end_.load(std::memory_order_acquire);
  if (s < 0) return e;
  return std::max(s, e - static_cast<int64_t>(cap_));
}

int64_t ReplayRing::frame_of_seconds(double t) const { return rate_ > 0 ? std::llround(t * rate_) : 0; }

bool ReplayRing::play(int64_t from, int64_t to) {
  if (!armed() || !frozen()) return false;
  from = std::max(from, first_frame());
  to = std::min(to, end_frame());
  if (to <= from) return false;
  req_from_.store(from, std::memory_order_relaxed);
  req_to_.store(to, std::memory_order_relaxed);
  req_seq_.fetch_add(1, std::memory_order_release);
  playing_.store(true, std::memory_order_seq_cst);
  return true;
}

void ReplayRing::stop_playback() { playing_.store(false, std::memory_order_seq_cst); }

int ReplayRing::copy(int64_t from, float* out, int n) const {
  const float* p = buf_.load(std::memory_order_acquire);
  if (!p || !frozen() || n <= 0 || from < first_frame() || from + n > end_frame()) return 0;
  for (int i = 0; i < n; ++i) out[i] = p[static_cast<size_t>((from + i) % static_cast<int64_t>(cap_))];
  return n;
}

void ReplayRing::on_input(const float* in, int n) {
  if (!in || n <= 0) return;
  in_busy_.store(true, std::memory_order_seq_cst);
  const int64_t f = frames_.load(std::memory_order_relaxed);
  if (recording_.load(std::memory_order_seq_cst)) {
    float* p = buf_.load(std::memory_order_seq_cst);
    if (p) {
      if (start_.load(std::memory_order_relaxed) < 0) start_.store(f, std::memory_order_relaxed);
      const int64_t cap = static_cast<int64_t>(cap_);
      int done = 0;
      // keep only the newest cap frames of a block longer than the ring
      if (n > cap) done = n - static_cast<int>(cap);
      while (done < n) {
        const int64_t at = (f + done) % cap;
        const int m = static_cast<int>(std::min<int64_t>(n - done, cap - at));
        std::memcpy(p + at, in + done, sizeof(float) * static_cast<size_t>(m));
        done += m;
      }
      end_.store(f + n, std::memory_order_release);
    }
  }
  frames_.store(f + n, std::memory_order_release);
  in_busy_.store(false, std::memory_order_seq_cst);
}

bool ReplayRing::on_output(float* out, int n) {
  if (!out || n <= 0) return false;
  out_busy_.store(true, std::memory_order_seq_cst);
  bool wrote = false;
  const float* p = buf_.load(std::memory_order_seq_cst);
  if (p && playing_.load(std::memory_order_seq_cst)) {
    const uint32_t seq = req_seq_.load(std::memory_order_acquire);
    if (seq != seen_seq_) {
      seen_seq_ = seq;
      from_ = req_from_.load(std::memory_order_relaxed);
      to_ = req_to_.load(std::memory_order_relaxed);
      pos_ = from_;
    }
    const int64_t cap = static_cast<int64_t>(cap_);
    const int k = static_cast<int>(std::max<int64_t>(0, std::min<int64_t>(n, to_ - pos_)));
    for (int i = 0; i < k; ++i) {
      const int64_t f = pos_ + i;
      float g = 1.f;
      if (f - from_ < fade_) g = static_cast<float>(f - from_) / static_cast<float>(fade_);
      if (to_ - 1 - f < fade_) g = std::min(g, static_cast<float>(to_ - 1 - f) / static_cast<float>(fade_));
      out[i] = g * p[static_cast<size_t>(f % cap)];
    }
    if (k < n) std::memset(out + k, 0, sizeof(float) * static_cast<size_t>(n - k));
    pos_ += k;
    if (pos_ >= to_) playing_.store(false, std::memory_order_seq_cst);
    wrote = true;
  }
  out_busy_.store(false, std::memory_order_seq_cst);
  return wrote;
}

}  // namespace intono_shim
