// The Oboe layer (ADR 0009): opens the microphone stream and, on demand, the drone output stream, and connects both to an AudioPump.
// Android only. Everything here runs on the caller's (UI) thread except the two callbacks, which only call AudioPump.
#pragma once
#include <atomic>
#include <memory>
#include <mutex>
#include <string>

#include <oboe/Oboe.h>

#include "audio_pump.hpp"
#include "soak.hpp"

namespace intono_shim {

struct SessionOptions {
  // Soak (bench mode, ADR 0008 W3/W4 and the polling power cost): soak_minutes > 0 arms the worker latency probe for that long and
  // samples the queue once a second. inline_engine: no worker thread (the battery baseline; the product is always threaded).
  int soak_minutes = 0;
  bool inline_engine = false;
};

class OboeSession {
 public:
  // Opens the input stream (low latency, exclusive if granted, float, mono, Unprocessed preset), creates the engine at the stream's
  // sample rate, and starts capture. nullptr on failure, with *error set.
  static std::unique_ptr<OboeSession> start(std::string* error, const SessionOptions& opts = {});
  ~OboeSession();   // stops and closes the streams first, then destroys the engine

  // Opens (enabled) or closes the output stream that renders the engine's drone. False if the stream cannot be opened. The stream
  // stays open while a replay review needs it.
  bool set_drone(bool enabled, int midi_note, float gain);

  // Replay (ADR 0013), all UI thread: the pump's RAM ring at the input rate. play() opens the output stream if the drone has not;
  // release() zeroes and frees the ring and closes the output stream unless the drone uses it. Times are the engine's (seconds).
  bool replay_arm(double seconds);
  void replay_freeze();
  bool replay_play(double from_s, double to_s);
  void replay_stop();
  void replay_release();
  bool replay_playing() const;
  bool healthy() const { return !input_lost_.load(std::memory_order_acquire); }   // false after a disconnect: restart the session
  intono_engine* engine() const { return engine_; }
  std::string info();   // settings and timing text, never audio

  // Soak sessions only: a progress line, and the end of the run (stream facts, then capture stops, then the soak numbers). After
  // finish_soak() the session captures nothing; destroy it.
  std::string soak_status();
  std::string finish_soak();

 private:
  OboeSession() = default;
  bool open_output_locked();    // mu_ held: opens and starts the output stream if it is not open
  void close_output_locked();   // mu_ held
  bool in_review_ = false;      // mu_: the ring is frozen for a review, so the output stream may be needed

  struct InputCallback;
  struct OutputCallback;
  struct ErrorCallback;

  std::mutex mu_;   // serialises the UI-thread calls; never taken by a callback
  intono_engine* engine_ = nullptr;
  std::unique_ptr<AudioPump> pump_;
  int sample_rate_ = 0;
  std::atomic<bool> input_lost_{false}, output_lost_{false};
  std::shared_ptr<InputCallback> in_cb_;
  std::shared_ptr<OutputCallback> out_cb_;
  std::shared_ptr<oboe::AudioStream> in_, out_;
  std::unique_ptr<SoakMonitor> soak_;
  double soak_t0_ = 0, soak_cpu0_ = 0, soak_planned_s_ = 0;
};

}  // namespace intono_shim
