// The iOS audio shim (ADR 0010): AVAudioSession + AVAudioEngine with a real-time sink node (capture) and source node (drone), both
// connected to the same portable AudioPump as Android. Compiled with ARC. The render blocks touch only the pump (no Objective-C messaging,
// no allocation, no locks); everything else runs on the main thread.
#import <AVFAudio/AVFAudio.h>

#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "audio_pump.hpp"
#include "bench.hpp"
#include "engine_internal.hpp"
#include "intono/intono.h"
#include "intono_ios.h"
#include "pump_text.hpp"
#include "soak.hpp"

using namespace intono_shim;

struct intono_ios_session {
  AVAudioEngine* engine = nil;
  AVAudioSinkNode* sink = nil;
  AVAudioSourceNode* source = nil;
  id interruption_observer = nil;
  id reset_observer = nil;
  id config_observer = nil;
  intono_engine* ie = nullptr;
  std::unique_ptr<AudioPump> pump;
  std::unique_ptr<SoakMonitor> soak;
  double soak_t0 = 0, soak_cpu0 = 0, soak_planned_s = 0;
  double sample_rate = 0;
  bool engine_running = false;
  std::atomic<bool> lost{false};
};

namespace {

int copy_out(const std::string& s, char* out, int cap) {
  if (out && cap > 0) std::snprintf(out, static_cast<size_t>(cap), "%s", s.c_str());
  return static_cast<int>(s.size());
}

std::string describe(NSError* e) { return e ? std::string(e.localizedDescription.UTF8String ?: "unknown") : std::string("unknown"); }

const char* port_type(NSArray<AVAudioSessionPortDescription*>* ports) {
  AVAudioSessionPortDescription* p = ports.firstObject;
  return p ? (p.portType.UTF8String ?: "?") : "none";
}

void stop_engine(intono_ios_session* s) {
  NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
  if (s->interruption_observer) [nc removeObserver:s->interruption_observer];
  if (s->reset_observer) [nc removeObserver:s->reset_observer];
  if (s->config_observer) [nc removeObserver:s->config_observer];
  s->interruption_observer = s->reset_observer = s->config_observer = nil;
  if (s->engine && s->engine_running) [s->engine stop];   // synchronous: no render block runs after it returns
  s->engine_running = false;
  if (s->engine) {
    if (s->sink) [s->engine detachNode:s->sink];
    if (s->source) [s->engine detachNode:s->source];
  }
  s->sink = nil;
  s->source = nil;
  s->engine = nil;
  [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

void destroy(intono_ios_session* s) {
  if (s->soak) s->soak->stop_sampler();
  stop_engine(s);
  s->pump.reset();
  if (s->ie) intono_destroy(s->ie);
  s->ie = nullptr;
  delete s;
}

}  // namespace

extern "C" intono_ios_session* intono_ios_start(int soak_minutes, int inline_engine, char* err, int err_cap) {
  @autoreleasepool {
    auto fail = [&](const std::string& m, intono_ios_session* s) -> intono_ios_session* {
      copy_out(m, err, err_cap);
      if (s) destroy(s);
      return nullptr;
    };
    copy_out("", err, err_cap);
    AVAudioSession* as = [AVAudioSession sharedInstance];
    NSError* e = nil;
    // .measurement: no voice processing, AGC or EQ (the counterpart of Oboe's Unprocessed preset).
    if (![as setCategory:AVAudioSessionCategoryPlayAndRecord
                    mode:AVAudioSessionModeMeasurement
                 options:(AVAudioSessionCategoryOptionAllowBluetoothA2DP | AVAudioSessionCategoryOptionDefaultToSpeaker)
                   error:&e])
      return fail("audio session category: " + describe(e), nullptr);
    [as setPreferredIOBufferDuration:0.005 error:nil];   // a preference: the granted value is reported by info()
    if (![as setActive:YES error:&e]) return fail("audio session activation: " + describe(e), nullptr);

    auto* s = new intono_ios_session();
    s->engine = [[AVAudioEngine alloc] init];
    AVAudioInputNode* input = s->engine.inputNode;
    AVAudioFormat* in_fmt = [input inputFormatForBus:0];
    if (in_fmt.sampleRate <= 0 || in_fmt.channelCount == 0) return fail("no input device (input format has no channels or no sample rate)", s);
    if (in_fmt.isInterleaved && in_fmt.channelCount > 1) return fail("unsupported input format: interleaved multi-channel", s);
    s->sample_rate = in_fmt.sampleRate;

    intono_config c{};
    c.sample_rate = static_cast<float>(s->sample_rate);
    c.window_size = 1024;
    c.hop_size = 256;
    c.a4_hz = 440.f;
    c.tuning = 0;
    c.min_hz = 180.f;
    c.max_hz = 3200.f;
    s->ie = inline_engine ? intono_internal::create(&c, true) : intono_create(&c);
    if (!s->ie) return fail("intono_create failed for sample rate " + std::to_string(s->sample_rate), s);
    if (soak_minutes > 0 && !inline_engine) {   // armed before the first intono_process, as the probe requires
      const double hops_per_s = s->sample_rate / c.hop_size;
      intono_internal::enable_probe(s->ie, static_cast<size_t>(hops_per_s * 60.0 * soak_minutes * 1.05) + 1024);
    }
    PumpConfig pc;
    pc.sample_rate = static_cast<int>(std::lround(s->sample_rate));
    pc.hop_size = c.hop_size;
    s->pump = std::make_unique<AudioPump>(engine_ops(s->ie), pc);
    AudioPump* pump = s->pump.get();

    // Capture: channel 0 of the hardware format (non-interleaved float), on the real-time render thread. The stream position is the
    // timestamp's sample time, so a jump of it is a gap (ADR 0009 Note 2).
    s->sink = [[AVAudioSinkNode alloc] initWithReceiverBlock:^OSStatus(const AudioTimeStamp* ts, AVAudioFrameCount n, const AudioBufferList* list) {
      if (!list || list->mNumberBuffers < 1 || !list->mBuffers[0].mData) return noErr;
      InputInfo info;
      info.position = (ts && (ts->mFlags & kAudioTimeStampSampleTimeValid)) ? static_cast<int64_t>(ts->mSampleTime) : -1;
      pump->on_input(static_cast<const float*>(list->mBuffers[0].mData), static_cast<int>(n), info);
      return noErr;
    }];
    [s->engine attachNode:s->sink];
    [s->engine connect:input to:s->sink format:in_fmt];

    // Drone: a mono source node into the main mixer, silent while the drone is off.
    AVAudioFormat* mono = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:s->sample_rate channels:1];
    s->source = [[AVAudioSourceNode alloc] initWithFormat:mono
                                              renderBlock:^OSStatus(BOOL* silence, const AudioTimeStamp*, AVAudioFrameCount n, AudioBufferList* out) {
      if (!out || out->mNumberBuffers < 1 || !out->mBuffers[0].mData) return noErr;
      float* d = static_cast<float*>(out->mBuffers[0].mData);
      if (!pump->drone_enabled()) {
        for (UInt32 b = 0; b < out->mNumberBuffers; ++b) std::memset(out->mBuffers[b].mData, 0, out->mBuffers[b].mDataByteSize);
        *silence = YES;
        return noErr;
      }
      pump->on_output(d, static_cast<int>(n));
      for (UInt32 b = 1; b < out->mNumberBuffers; ++b) std::memcpy(out->mBuffers[b].mData, d, sizeof(float) * n);
      return noErr;
    }];
    [s->engine attachNode:s->source];
    [s->engine connect:s->source to:s->engine.mainMixerNode format:mono];

    std::atomic<bool>* lost = &s->lost;   // the observers are removed before the session is freed
    NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
    s->interruption_observer = [nc addObserverForName:AVAudioSessionInterruptionNotification object:as queue:nil usingBlock:^(NSNotification* note) {
      NSNumber* type = note.userInfo[AVAudioSessionInterruptionTypeKey];
      if (type.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan) lost->store(true, std::memory_order_release);
    }];
    s->reset_observer = [nc addObserverForName:AVAudioSessionMediaServicesWereResetNotification object:as queue:nil usingBlock:^(NSNotification*) {
      lost->store(true, std::memory_order_release);
    }];
    s->config_observer = [nc addObserverForName:AVAudioEngineConfigurationChangeNotification object:s->engine queue:nil usingBlock:^(NSNotification*) {
      lost->store(true, std::memory_order_release);   // the engine stopped itself (route or format change)
    }];

    if (soak_minutes > 0) {
      s->soak = std::make_unique<SoakMonitor>(s->ie, !inline_engine, pc.sample_rate);
      s->soak_planned_s = 60.0 * soak_minutes;
      s->soak_t0 = monotonic_seconds();
      s->soak_cpu0 = process_cpu_seconds();
      s->soak->start_sampler();
    }
    [s->engine prepare];
    if (![s->engine startAndReturnError:&e]) return fail("cannot start the audio engine: " + describe(e), s);
    s->engine_running = true;
    return s;
  }
}

extern "C" void intono_ios_stop(intono_ios_session* s) {
  if (!s) return;
  @autoreleasepool {
    destroy(s);
  }
}

extern "C" int intono_ios_healthy(const intono_ios_session* s) { return s && !s->lost.load(std::memory_order_acquire) ? 1 : 0; }

extern "C" intptr_t intono_ios_engine(const intono_ios_session* s) { return s ? reinterpret_cast<intptr_t>(s->ie) : 0; }

extern "C" int intono_ios_set_drone(intono_ios_session* s, int on, int midi_note, float gain) {
  if (!s || !s->ie || !s->pump) return 0;
  if (on) intono_drone_set(s->ie, midi_note, gain, 0);
  s->pump->set_drone_enabled(on != 0);
  return 1;
}

extern "C" int intono_ios_info(intono_ios_session* s, char* out, int cap) {
  if (!s) return copy_out("stopped", out, cap);
  @autoreleasepool {
    AVAudioSession* as = [AVAudioSession sharedInstance];
    char b[512];
    std::snprintf(b, sizeof b,
                  "input: AVAudioEngine, mode %s, %.0f Hz, IO buffer %.2f ms (granted; preferred 5.00), latency in %.1f ms / out %.1f ms "
                  "(reported by AVAudioSession), route in %s, out %s%s\n",
                  as.mode.UTF8String ?: "?", s->sample_rate, as.IOBufferDuration * 1000.0, as.inputLatency * 1000.0, as.outputLatency * 1000.0,
                  port_type(as.currentRoute.inputs), port_type(as.currentRoute.outputs), s->lost.load() ? ", LOST" : "");
    std::string t = b;
    t += s->pump && s->pump->drone_enabled() ? "output: drone on\n" : "output: drone off\n";
    if (s->pump) t += pump_text(*s->pump);
    return copy_out(t, out, cap);
  }
}

extern "C" int intono_ios_soak_status(intono_ios_session* s, char* out, int cap) {
  if (!s || !s->soak) return copy_out("not a soak session", out, cap);
  char b[64];
  std::snprintf(b, sizeof b, "%.1f of %.1f min: ", (monotonic_seconds() - s->soak_t0) / 60.0, s->soak_planned_s / 60.0);
  return copy_out(b + s->soak->status(), out, cap);
}

extern "C" int intono_ios_finish_soak(intono_ios_session* s, char* out, int cap) {
  if (!s || !s->soak) return copy_out("not a soak session", out, cap);
  const double wall = monotonic_seconds() - s->soak_t0;
  const double cpu = process_cpu_seconds() - s->soak_cpu0;
  std::vector<char> facts(8192);
  intono_ios_info(s, facts.data(), static_cast<int>(facts.size()));   // the stream facts while the engine still runs
  @autoreleasepool {
    stop_engine(s);   // no more intono_process after this
  }
  const SoakResult r = s->soak->finish(wall, cpu, s->soak_planned_s);   // reads the probe, which drains the worker
  return copy_out(r.text() + facts.data(), out, cap);
}

extern "C" int intono_ios_headphones(void) {
  @autoreleasepool {
    NSArray<AVAudioSessionPort>* kinds = @[ AVAudioSessionPortHeadphones, AVAudioSessionPortBluetoothA2DP, AVAudioSessionPortBluetoothHFP,
                                            AVAudioSessionPortBluetoothLE, AVAudioSessionPortUSBAudio ];
    for (AVAudioSessionPortDescription* p in [AVAudioSession sharedInstance].currentRoute.outputs)
      if ([kinds containsObject:p.portType]) return 1;
    return 0;
  }
}

extern "C" int intono_ios_smoke(void) {
  intono_config c{};
  c.sample_rate = 48000.f;
  c.window_size = 1024;
  c.hop_size = 256;
  c.a4_hz = 440.f;
  c.tuning = 0;
  c.min_hz = 180.f;
  c.max_hz = 3200.f;
  intono_engine* e = intono_create(&c);
  if (!e) return 0;
  std::vector<float> x(48000);
  for (size_t i = 0; i < x.size(); ++i) x[i] = 0.3f * static_cast<float>(std::sin(2.0 * M_PI * 440.0 * i / 48000.0));
  std::vector<intono_frame> f(256);
  int frames = 0, voiced_a4 = 0;
  for (size_t p = 0; p < x.size(); p += 128) {
    intono_process(e, x.data() + p, 128);
    int n;
    while ((n = intono_read_frames(e, f.data(), static_cast<int>(f.size()))) > 0) {
      frames += n;
      for (int i = 0; i < n; ++i) voiced_a4 += (f[i].is_voiced && f[i].midi_note == 69) ? 1 : 0;
    }
  }
  intono_destroy(e);
  return frames > 100 && voiced_a4 > frames / 2 ? 1 : 0;
}

// The C API Dart resolves with dlsym (DynamicLibrary.process()). An externally visible, `used` table, read through a volatile pointer: a
// function-local constant table was folded away by the optimiser (the count became a constant), so nothing referenced bench.cpp's object
// and the linker left intono_bench_run out of the app (first ios-app run).
extern "C" __attribute__((used, visibility("default"))) void* const intono_ios_c_api_table[] = {
    reinterpret_cast<void*>(&intono_create),       reinterpret_cast<void*>(&intono_destroy),
    reinterpret_cast<void*>(&intono_process),      reinterpret_cast<void*>(&intono_read_frames),
    reinterpret_cast<void*>(&intono_read_notes),   reinterpret_cast<void*>(&intono_set_tonic),
    reinterpret_cast<void*>(&intono_drone_set),    reinterpret_cast<void*>(&intono_drone_render),
    reinterpret_cast<void*>(&intono_bench_run),
};

extern "C" int intono_ios_link_c_api(void) {
  int n = 0;
  for (size_t i = 0; i < sizeof intono_ios_c_api_table / sizeof intono_ios_c_api_table[0]; ++i) {
    void* volatile p = intono_ios_c_api_table[i];
    n += p != nullptr ? 1 : 0;
  }
  return n;
}
