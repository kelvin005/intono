// ReplayRing (ADR 0013): the last seconds of a scale run, in RAM only, for replay on the review screen.
//
//   UI thread:      arm (allocates, zeroed) -> the run -> freeze (review: the microphone reaches neither the engine nor the ring) ->
//                   play / stop_playback -> release (stops playback, waits until neither audio thread touches the buffer, zeroes it,
//                   frees it). arm() on an armed ring releases the old run first. The destructor releases.
//   input thread:   on_input copies each block into the ring (no allocation, no lock). Every frame is counted, armed or not, so a
//                   frame number is the engine's own sample clock (both see the same frames, from the session's first one).
//   output thread:  on_output plays the requested slice (with 5 ms fades) and silences the rest of the block.
//
// Never written to disk, never passed to anything that persists it (ADR 0013). The audio threads and release() hand the buffer over
// with a pointer plus one busy flag per audio thread (seq_cst on both sides, so release() never frees a buffer a callback still uses).
#pragma once
#include <atomic>
#include <cstddef>
#include <cstdint>

namespace intono_shim {

class ReplayRing {
 public:
  // How the buffer is obtained and returned (tests inspect it at release). Default: calloc / free.
  struct Allocator {
    void* ctx = nullptr;
    float* (*alloc)(void* ctx, size_t n) = nullptr;            // n floats, zeroed
    void (*release)(void* ctx, float* p, size_t n) = nullptr;  // p is all zeros when this is called
  };

  ReplayRing();
  explicit ReplayRing(Allocator a);
  ~ReplayRing();
  ReplayRing(const ReplayRing&) = delete;
  ReplayRing& operator=(const ReplayRing&) = delete;

  // ---- UI thread ----
  bool arm(int sample_rate, double seconds);   // false if the buffer cannot be allocated (nothing is recorded then)
  void freeze();                               // the run is over: nothing more is recorded, and the pump stops feeding the engine
  void release();                              // idempotent
  bool play(int64_t from_frame, int64_t to_frame);   // frozen only; clamped to what is kept; false if that is empty
  void stop_playback();
  // Reads [from, from+n) if all of it is kept (frozen only); returns n or 0.
  int copy(int64_t from_frame, float* out, int n) const;

  // ---- any thread ----
  bool armed() const { return buf_.load(std::memory_order_acquire) != nullptr; }
  bool frozen() const { return frozen_.load(std::memory_order_acquire); }
  bool playing() const { return playing_.load(std::memory_order_acquire); }
  int64_t first_frame() const;   // the oldest kept frame (absolute)
  int64_t end_frame() const { return end_.load(std::memory_order_acquire); }   // one past the newest kept frame
  int64_t frame_of_seconds(double t) const;   // engine time (seconds since the session's first frame) to a frame
  int fade_frames() const { return fade_; }
  int sample_rate() const { return rate_; }

  // ---- audio threads ----
  void on_input(const float* in, int n);   // input thread
  bool on_output(float* out, int n);       // output thread: true if it wrote a playback block (silence after the slice's end)

 private:
  void wait_idle() const;

  Allocator alloc_;
  std::atomic<float*> buf_{nullptr};
  size_t cap_ = 0;     // written by the UI thread before buf_ is published
  int rate_ = 0;
  int fade_ = 0;
  std::atomic<bool> recording_{false}, frozen_{false}, playing_{false};
  std::atomic<bool> in_busy_{false}, out_busy_{false};
  std::atomic<int64_t> frames_{0};       // input thread: every frame seen, from the session's first
  std::atomic<int64_t> start_{-1};       // the first recorded frame of this run (-1: none yet)
  std::atomic<int64_t> end_{0};
  // playback (UI thread writes the request, output thread consumes it)
  std::atomic<int64_t> req_from_{0}, req_to_{0};
  std::atomic<uint32_t> req_seq_{0};
  uint32_t seen_seq_ = 0;   // output thread
  int64_t pos_ = 0, from_ = 0, to_ = 0;   // output thread
};

}  // namespace intono_shim
