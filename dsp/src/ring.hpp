// Lock-free single-producer / single-consumer ring buffer. Storage is allocated once
// in the constructor; push/pop never allocate, lock or block.
#pragma once
#include <atomic>
#include <cstddef>
#include <memory>

namespace intono {

template <typename T>
class SpscRing {
 public:
  explicit SpscRing(size_t capacity_pow2) : mask_(capacity_pow2 - 1), buf_(new T[capacity_pow2]) {}
  // Producer thread. Returns false (and counts a drop) when full; never overwrites.
  bool push(const T& v) {
    const size_t h = head_.load(std::memory_order_relaxed);
    const size_t t = tail_.load(std::memory_order_acquire);
    if (h - t > mask_) {
      dropped_.fetch_add(1, std::memory_order_relaxed);
      return false;
    }
    buf_[h & mask_] = v;
    head_.store(h + 1, std::memory_order_release);
    return true;
  }
  // Consumer thread.
  bool pop(T& out) {
    const size_t t = tail_.load(std::memory_order_relaxed);
    const size_t h = head_.load(std::memory_order_acquire);
    if (t == h) return false;
    out = buf_[t & mask_];
    tail_.store(t + 1, std::memory_order_release);
    return true;
  }
  size_t size() const { return head_.load(std::memory_order_acquire) - tail_.load(std::memory_order_acquire); }
  size_t capacity() const { return mask_ + 1; }
  size_t dropped() const { return dropped_.load(std::memory_order_relaxed); }

 private:
  const size_t mask_;
  std::unique_ptr<T[]> buf_;
  alignas(64) std::atomic<size_t> head_{0};
  alignas(64) std::atomic<size_t> tail_{0};
  std::atomic<size_t> dropped_{0};
};

}  // namespace intono
