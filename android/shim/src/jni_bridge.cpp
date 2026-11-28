// JNI entry points for com.example.intono.NativeAudio (ADR 0009). Thin: lifecycle and text only; no audio crosses JNI.
#include <jni.h>

#include <cmath>
#include <mutex>
#include <string>
#include <vector>

#include "intono/intono.h"
#include "oboe_audio.hpp"

using intono_shim::OboeSession;

namespace {
std::mutex g_error_mu;
std::string g_last_error;
void set_error(const std::string& e) {
  std::lock_guard<std::mutex> l(g_error_mu);
  g_last_error = e;
}
OboeSession* session(jlong h) { return reinterpret_cast<OboeSession*>(h); }
}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL Java_com_example_intono_NativeAudio_nativeStart(JNIEnv*, jobject) {
  std::string err;
  std::unique_ptr<OboeSession> s = OboeSession::start(&err);
  if (!s) {
    set_error(err);
    return 0;
  }
  set_error("");
  return reinterpret_cast<jlong>(s.release());
}

JNIEXPORT void JNICALL Java_com_example_intono_NativeAudio_nativeStop(JNIEnv*, jobject, jlong h) { delete session(h); }

// Bench-mode soak (ADR 0008 W3/W4, polling power cost): the same capture with the worker latency probe armed and the queue sampled once a
// second; inlineEngine runs without the worker thread (the battery baseline).
JNIEXPORT jlong JNICALL Java_com_example_intono_NativeAudio_nativeStartSoak(JNIEnv*, jobject, jint minutes, jboolean inlineEngine) {
  intono_shim::SessionOptions o;
  o.soak_minutes = minutes > 0 ? minutes : 1;
  o.inline_engine = inlineEngine == JNI_TRUE;
  std::string err;
  std::unique_ptr<OboeSession> s = OboeSession::start(&err, o);
  if (!s) {
    set_error(err);
    return 0;
  }
  set_error("");
  return reinterpret_cast<jlong>(s.release());
}

JNIEXPORT jstring JNICALL Java_com_example_intono_NativeAudio_nativeSoakStatus(JNIEnv* env, jobject, jlong h) {
  return env->NewStringUTF(session(h)->soak_status().c_str());
}

JNIEXPORT jstring JNICALL Java_com_example_intono_NativeAudio_nativeFinishSoak(JNIEnv* env, jobject, jlong h) {
  return env->NewStringUTF(session(h)->finish_soak().c_str());
}

JNIEXPORT jboolean JNICALL Java_com_example_intono_NativeAudio_nativeHealthy(JNIEnv*, jobject, jlong h) {
  return session(h)->healthy() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlong JNICALL Java_com_example_intono_NativeAudio_nativeEnginePointer(JNIEnv*, jobject, jlong h) {
  return reinterpret_cast<jlong>(session(h)->engine());
}

JNIEXPORT jboolean JNICALL Java_com_example_intono_NativeAudio_nativeSetDrone(JNIEnv*, jobject, jlong h, jboolean on, jint midi, jfloat gain) {
  return session(h)->set_drone(on == JNI_TRUE, midi, gain) ? JNI_TRUE : JNI_FALSE;
}

// Replay (ADR 0013): the audio stays in the pump's RAM ring; nothing here passes audio to Java.
JNIEXPORT jboolean JNICALL Java_com_example_intono_NativeAudio_nativeReplayArm(JNIEnv*, jobject, jlong h, jdouble seconds) {
  return session(h)->replay_arm(seconds) ? JNI_TRUE : JNI_FALSE;
}
JNIEXPORT void JNICALL Java_com_example_intono_NativeAudio_nativeReplayFreeze(JNIEnv*, jobject, jlong h) { session(h)->replay_freeze(); }
JNIEXPORT jboolean JNICALL Java_com_example_intono_NativeAudio_nativeReplayPlay(JNIEnv*, jobject, jlong h, jdouble from, jdouble to) {
  return session(h)->replay_play(from, to) ? JNI_TRUE : JNI_FALSE;
}
JNIEXPORT void JNICALL Java_com_example_intono_NativeAudio_nativeReplayStop(JNIEnv*, jobject, jlong h) { session(h)->replay_stop(); }
JNIEXPORT void JNICALL Java_com_example_intono_NativeAudio_nativeReplayRelease(JNIEnv*, jobject, jlong h) { session(h)->replay_release(); }
JNIEXPORT jboolean JNICALL Java_com_example_intono_NativeAudio_nativeReplayPlaying(JNIEnv*, jobject, jlong h) {
  return session(h)->replay_playing() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL Java_com_example_intono_NativeAudio_nativeInfo(JNIEnv* env, jobject, jlong h) {
  return env->NewStringUTF(session(h)->info().c_str());
}

JNIEXPORT jstring JNICALL Java_com_example_intono_NativeAudio_nativeLastError(JNIEnv* env, jobject) {
  std::lock_guard<std::mutex> l(g_error_mu);
  return env->NewStringUTF(g_last_error.c_str());
}

// Engine create / process / read / destroy with a generated 440 Hz tone, no audio device (the CI emulator has none).
JNIEXPORT jboolean JNICALL Java_com_example_intono_NativeAudio_nativeSmoke(JNIEnv*, jobject) {
  intono_config c{};
  c.sample_rate = 48000.f; c.window_size = 1024; c.hop_size = 256; c.a4_hz = 440.f; c.tuning = 0; c.min_hz = 180.f; c.max_hz = 3200.f;
  intono_engine* e = intono_create(&c);
  if (!e) return JNI_FALSE;
  std::vector<float> x(24000);
  for (size_t i = 0; i < x.size(); ++i) x[i] = static_cast<float>(0.4 * std::sin(2.0 * 3.14159265358979323846 * 440.0 * static_cast<double>(i) / 48000.0));
  intono_process(e, x.data(), static_cast<int>(x.size()));
  std::vector<intono_frame> f(256);
  const int n = intono_read_frames(e, f.data(), 256);
  bool ok = n > 50 && f[n - 1].is_voiced != 0 && f[n - 1].midi_note == 69 && std::fabs(f[n - 1].cents) < 5.f;
  intono_destroy(e);
  return ok ? JNI_TRUE : JNI_FALSE;
}

}  // extern "C"
