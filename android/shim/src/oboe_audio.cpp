#include "oboe_audio.hpp"
#include "pump_text.hpp"

#include <android/log.h>

#include <cstdio>

#include "engine_internal.hpp"

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

std::unique_ptr<OboeSession> OboeSession::start(std::string* error, const SessionOptions& opts) {
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
  s->engine_ = opts.inline_engine ? intono_internal::create(&c, true) : intono_create(&c);
  if (s->engine_ && opts.soak_minutes > 0 && !opts.inline_engine) {   // armed before the first intono_process, as the probe requires
    const double hops_per_s = static_cast<double>(s->sample_rate_) / c.hop_size;
    intono_internal::enable_probe(s->engine_, static_cast<size_t>(hops_per_s * 60.0 * opts.soak_minutes * 1.05) + 1024);
  }
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
  if (opts.soak_minutes > 0) {
    s->soak_ = std::make_unique<SoakMonitor>(s->engine_, !opts.inline_engine, s->sample_rate_);
    s->soak_planned_s_ = 60.0 * opts.soak_minutes;
    s->soak_t0_ = monotonic_seconds();
    s->soak_cpu0_ = process_cpu_seconds();
    s->soak_->start_sampler();
  }
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
  if (soak_) soak_->stop_sampler();
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
  // Latency (ADR 0009 decision 5): measured from the stream's own timestamps where the device provides them (not right after start);
  // otherwise the reason Oboe gives, and the burst-based estimate, marked as an estimate. For input the estimate is a lower bound: one
  // burst has to be captured before the app sees it (converter and driver delays come on top).
  const auto latency = [&](oboe::AudioStream& st, char* out, size_t cap) {
    const auto l = st.calculateLatencyMillis();
    const int rate = st.getSampleRate();
    const double burst_ms = rate > 0 ? 1000.0 * st.getFramesPerBurst() / rate : 0.0;
    const double buffer_ms = rate > 0 ? 1000.0 * st.getBufferSizeInFrames() / rate : 0.0;
    if (l) {
      std::snprintf(out, cap, ", latency %.1f ms (timestamps)", l.value());
    } else if (st.getDirection() == oboe::Direction::Input) {
      std::snprintf(out, cap, ", latency n/a from timestamps (%s); estimate >= %.1f ms (one burst)", oboe::convertToText(l.error()), burst_ms);
    } else {
      std::snprintf(out, cap, ", latency n/a from timestamps (%s); estimate %.1f ms (buffer)", oboe::convertToText(l.error()), buffer_ms);
    }
  };
  if (in_) {
    char lat[160];
    latency(*in_, lat, sizeof lat);
    std::snprintf(buf, sizeof buf, "input: %s, %s, %s, preset %s, %d Hz, burst %d, buffer %d%s%s\n",
                  oboe::convertToText(in_->getAudioApi()), oboe::convertToText(in_->getSharingMode()),
                  oboe::convertToText(in_->getPerformanceMode()), oboe::convertToText(in_->getInputPreset()), in_->getSampleRate(),
                  in_->getFramesPerBurst(), in_->getBufferSizeInFrames(), lat, input_lost_.load() ? ", LOST" : "");
    s += buf;
  }
  if (out_) {
    char lat[160];
    latency(*out_, lat, sizeof lat);
    std::snprintf(buf, sizeof buf, "output: %s, %s, %s, %d Hz, burst %d, buffer %d%s%s\n", oboe::convertToText(out_->getAudioApi()),
                  oboe::convertToText(out_->getSharingMode()), oboe::convertToText(out_->getPerformanceMode()), out_->getSampleRate(),
                  out_->getFramesPerBurst(), out_->getBufferSizeInFrames(), lat, output_lost_.load() ? ", LOST" : "");
    s += buf;
  } else {
    s += "output: drone off\n";
  }
  if (pump_) s += pump_text(*pump_);
  return s;
}

std::string OboeSession::soak_status() {
  if (!soak_) return "not a soak session";
  char b[64];
  std::snprintf(b, sizeof b, "%.1f of %.1f min: ", (monotonic_seconds() - soak_t0_) / 60.0, soak_planned_s_ / 60.0);
  return b + soak_->status();
}

std::string OboeSession::finish_soak() {
  if (!soak_) return "not a soak session";
  const double wall = monotonic_seconds() - soak_t0_;
  const double cpu = process_cpu_seconds() - soak_cpu0_;
  std::string facts = info();   // the stream facts while the stream still exists
  {
    std::lock_guard<std::mutex> lock(mu_);
    if (pump_) pump_->set_drone_enabled(false);
    if (out_) { out_->requestStop(); out_->close(); out_.reset(); }
    if (in_) { in_->requestStop(); in_->close(); in_.reset(); }   // close() returns after the last callback: no more intono_process
  }
  const SoakResult r = soak_->finish(wall, cpu, soak_planned_s_);   // reads the probe, which drains the worker
  return r.text() + facts;
}

}  // namespace intono_shim
