#include "oboe_audio.hpp"

#include <android/log.h>

#include <cstdio>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "intono", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "intono", __VA_ARGS__)

namespace intono_shim {

struct OboeSession::InputCallback : oboe::AudioStreamDataCallback {
  std::atomic<AudioPump*> pump{nullptr};
  uint32_t n = 0;
  int64_t last_xruns = -1;
  oboe::DataCallbackResult onAudioReady(oboe::AudioStream* s, void* data, int32_t frames) override {
    AudioPump* p = pump.load(std::memory_order_acquire);
    if (!p) return oboe::DataCallbackResult::Continue;
    InputInfo info;
    info.position = s->getFramesRead();   // the stream's own frame counter: a gap is a jump of it (ADR 0009 Note 2)
    if ((n++ & 15u) == 0) {               // the overrun count is polled, not read every callback
      const auto x = s->getXRunCount();
      last_xruns = x ? static_cast<int64_t>(x.value()) : -1;
    }
    info.xruns = last_xruns;
    p->on_input(static_cast<const float*>(data), frames, info);
    return oboe::DataCallbackResult::Continue;
  }
};

struct OboeSession::OutputCallback : oboe::AudioStreamDataCallback {
  std::atomic<AudioPump*> pump{nullptr};
  uint32_t n = 0;
  oboe::DataCallbackResult onAudioReady(oboe::AudioStream* s, void* data, int32_t frames) override {
    AudioPump* p = pump.load(std::memory_order_acquire);
    if (!p) return oboe::DataCallbackResult::Stop;
    p->on_output(static_cast<float*>(data), frames);
    if ((++n & 63u) == 0) {
      const auto x = s->getXRunCount();
      if (x) p->set_output_xruns(static_cast<uint64_t>(x.value()));
    }
    return oboe::DataCallbackResult::Continue;
  }
};

struct OboeSession::ErrorCallback : oboe::AudioStreamErrorCallback {
  explicit ErrorCallback(std::atomic<bool>* f) : flag(f) {}
  std::atomic<bool>* flag;
  void onErrorAfterClose(oboe::AudioStream*, oboe::Result r) override {
    LOGE("stream error after close: %s", oboe::convertToText(r));
    flag->store(true, std::memory_order_release);
  }
};

std::unique_ptr<OboeSession> OboeSession::start(std::string* error) {
  std::unique_ptr<OboeSession> s(new OboeSession());
  s->in_cb_ = std::make_shared<InputCallback>();
  oboe::AudioStreamBuilder b;
  b.setDirection(oboe::Direction::Input)
      ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
      ->setSharingMode(oboe::SharingMode::Exclusive)   // may be granted shared: the granted mode is reported by info()
      ->setFormat(oboe::AudioFormat::Float)
      ->setChannelCount(oboe::ChannelCount::Mono)
      ->setInputPreset(oboe::InputPreset::Unprocessed)   // no AGC, noise suppression or echo cancellation
      ->setDataCallback(s->in_cb_)
      ->setErrorCallback(std::make_shared<ErrorCallback>(&s->input_lost_));
  const oboe::Result r = b.openStream(s->in_);
  if (r != oboe::Result::OK) {
    *error = std::string("cannot open the microphone stream: ") + oboe::convertToText(r);
    return nullptr;
  }
  s->sample_rate_ = s->in_->getSampleRate();

  intono_config c{};
  c.sample_rate = static_cast<float>(s->sample_rate_);
  c.window_size = 1024;
  c.hop_size = 256;
  c.a4_hz = 440.f;
  c.tuning = 0;
  c.min_hz = 180.f;
  c.max_hz = 3200.f;
  s->engine_ = intono_create(&c);
  if (!s->engine_) {
    *error = "intono_create failed for sample rate " + std::to_string(s->sample_rate_);
    s->in_->close();
    return nullptr;
  }
  PumpConfig pc;
  pc.sample_rate = s->sample_rate_;
  pc.hop_size = c.hop_size;
  s->pump_ = std::make_unique<AudioPump>(engine_ops(s->engine_), pc);
  s->in_cb_->pump.store(s->pump_.get(), std::memory_order_release);
  const oboe::Result st = s->in_->requestStart();
  if (st != oboe::Result::OK) {
    *error = std::string("cannot start the microphone stream: ") + oboe::convertToText(st);
    return nullptr;   // the destructor closes the stream and destroys the engine
  }
  LOGI("input: %s, %s, %d Hz, burst %d", oboe::convertToText(s->in_->getSharingMode()), oboe::convertToText(s->in_->getAudioApi()),
       s->sample_rate_, s->in_->getFramesPerBurst());
  return s;
}

OboeSession::~OboeSession() {
  if (pump_) pump_->set_drone_enabled(false);
  if (out_) { out_->requestStop(); out_->close(); out_.reset(); }
  if (in_) { in_->requestStop(); in_->close(); in_.reset(); }   // close() returns after the last callback
  pump_.reset();
  if (engine_) intono_destroy(engine_);
}

bool OboeSession::set_drone(bool enabled, int midi_note, float gain) {
  std::lock_guard<std::mutex> lock(mu_);
  if (!engine_) return false;
  if (!enabled) {
    pump_->set_drone_enabled(false);
    if (out_) { out_->requestStop(); out_->close(); out_.reset(); out_cb_.reset(); }
    return true;
  }
  intono_drone_set(engine_, midi_note, gain, 0);
  if (!out_) {
    out_cb_ = std::make_shared<OutputCallback>();
    output_lost_.store(false);
    oboe::AudioStreamBuilder b;
    b.setDirection(oboe::Direction::Output)
        ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
        ->setSharingMode(oboe::SharingMode::Exclusive)
        ->setFormat(oboe::AudioFormat::Float)
        ->setChannelCount(oboe::ChannelCount::Mono)
        ->setSampleRate(sample_rate_)
        ->setSampleRateConversionQuality(oboe::SampleRateConversionQuality::Medium)
        ->setUsage(oboe::Usage::Media)
        ->setContentType(oboe::ContentType::Music)
        ->setDataCallback(out_cb_)
        ->setErrorCallback(std::make_shared<ErrorCallback>(&output_lost_));
    const oboe::Result r = b.openStream(out_);
    if (r != oboe::Result::OK) {
      LOGE("cannot open the drone stream: %s", oboe::convertToText(r));
      out_.reset();
      out_cb_.reset();
      return false;
    }
    out_->setBufferSizeInFrames(2 * out_->getFramesPerBurst());
    out_cb_->pump.store(pump_.get(), std::memory_order_release);
  }
  pump_->set_drone_enabled(true);
  return out_->requestStart() == oboe::Result::OK;
}

std::string OboeSession::info() {
  std::lock_guard<std::mutex> lock(mu_);
  char buf[1024];
  std::string s;
  if (in_) {
    std::snprintf(buf, sizeof buf, "input: %s, %s, %s, preset %s, %d Hz, burst %d, buffer %d%s\n",
                  oboe::convertToText(in_->getAudioApi()), oboe::convertToText(in_->getSharingMode()),
                  oboe::convertToText(in_->getPerformanceMode()), oboe::convertToText(in_->getInputPreset()), in_->getSampleRate(),
                  in_->getFramesPerBurst(), in_->getBufferSizeInFrames(), input_lost_.load() ? ", LOST" : "");
    s += buf;
  }
  if (out_) {
    std::snprintf(buf, sizeof buf, "output: %s, %s, %s, %d Hz, burst %d, buffer %d%s\n", oboe::convertToText(out_->getAudioApi()),
                  oboe::convertToText(out_->getSharingMode()), oboe::convertToText(out_->getPerformanceMode()), out_->getSampleRate(),
                  out_->getFramesPerBurst(), out_->getBufferSizeInFrames(), output_lost_.load() ? ", LOST" : "");
    s += buf;
  } else {
    s += "output: drone off\n";
  }
  if (pump_) {
    const PumpStats p = pump_->snapshot();
    const auto ull = [](uint64_t v) { return static_cast<unsigned long long>(v); };
    std::snprintf(buf, sizeof buf, "hop us: median %.1f, p99 %.1f, max %.1f (%llu hops); slow (> 1000 us): %llu\ncallback us: max %.1f\n",
                  p.chunk.p50_ns / 1e3, p.chunk.p99_ns / 1e3, p.chunk.max_ns / 1e3, ull(p.chunk.count), ull(p.slow_hops),
                  p.callback.max_ns / 1e3);
    s += buf;
    std::snprintf(buf, sizeof buf, "input gaps (stream position): %llu, %llu frames lost%s; stream overruns %llu; late callbacks (wall clock) %llu\n",
                  ull(p.input_gaps), ull(p.gap_frames), p.position_supported ? "" : " [position counter not moving: gaps unmeasured]",
                  ull(p.input_overruns), ull(p.late_callbacks));
    s += buf;
    std::snprintf(buf, sizeof buf, "output xruns %llu\n", ull(p.output_xruns));
    s += buf;
    // Times are CLOCK_MONOTONIC seconds, the same clock as the Dart side's frame timings, so slow hops can be matched to UI jank.
    const auto list = [&](const char* title, const std::vector<PumpEvent>& ev, const char* unit) {
      if (ev.empty()) return;
      s += title;
      const size_t from = ev.size() > 8 ? ev.size() - 8 : 0;
      for (size_t i = from; i < ev.size(); ++i) {
        std::snprintf(buf, sizeof buf, " %.3f:%llu%s", static_cast<double>(p.epoch_ns) / 1e9 + ev[i].t_s, ull(ev[i].value), unit);
        s += buf;
      }
      s += '\n';
    };
    list("slow hops (t s, us):", pump_->events(EventKind::SlowHop), "us");
    list("gaps (t s, frames):", pump_->events(EventKind::PositionGap), "f");
    list("overruns (t s, count):", pump_->events(EventKind::Overrun), "");
  }
  return s;
}

}  // namespace intono_shim
