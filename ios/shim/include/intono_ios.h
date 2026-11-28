// C API of the iOS audio shim (ADR 0010), called by the Swift plugin (app/packages/intono_ios). Lifecycle and text only: no audio
// crosses it. Dart reads frames and notes from the engine itself over dart:ffi (DynamicLibrary.process()).
// Every function is for the main (UI) thread; the AVAudioEngine render blocks call only AudioPump.
#ifndef INTONO_IOS_H
#define INTONO_IOS_H
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct intono_ios_session intono_ios_session;

// Configures AVAudioSession (.playAndRecord, mode .measurement, 5 ms preferred IO buffer), creates the engine at the hardware rate and
// starts capture. soak_minutes > 0 arms the soak (worker latency probe, queue sampled once a second); inline_engine != 0 runs without the
// worker thread (the battery baseline). NULL on failure, with the reason in err (always terminated).
intono_ios_session* intono_ios_start(int soak_minutes, int inline_engine, char* err, int err_cap);
// Stops the engine, deactivates the session and destroys the engine. NULL is ignored.
void intono_ios_stop(intono_ios_session* s);
// 0 after an interruption, a media-services reset or an engine configuration change: restart the session.
int intono_ios_healthy(const intono_ios_session* s);
// The intono_engine* for dart:ffi, as an integer.
intptr_t intono_ios_engine(const intono_ios_session* s);
// Drone on (the source node renders intono_drone_render) or off (silence).
int intono_ios_set_drone(intono_ios_session* s, int on, int midi_note, float gain);
// Replay (ADR 0013): the last `seconds` of input in RAM (arm, at a run's start; releases a previous run), frozen at the run's end (the
// microphone then reaches neither the engine nor the ring), played between two engine times in seconds, and released (zeroed, freed).
// Never written to disk. 1 = success / playing.
int intono_ios_replay_arm(intono_ios_session* s, double seconds);
void intono_ios_replay_freeze(intono_ios_session* s);
int intono_ios_replay_play(intono_ios_session* s, double from_s, double to_s);
void intono_ios_replay_stop(intono_ios_session* s);
void intono_ios_replay_release(intono_ios_session* s);
int intono_ios_replay_playing(const intono_ios_session* s);
// Freeze stops the session's engine (the microphone is off during review) and plays through an output-only engine; release stops it.
// For tests and the info text: 1 while the input (session) engine / the review output engine runs.
int intono_ios_input_running(const intono_ios_session* s);
int intono_ios_review_output_running(const intono_ios_session* s);
// Text into out (always terminated, truncated if needed); returns the full length.
int intono_ios_info(intono_ios_session* s, char* out, int cap);
int intono_ios_soak_status(intono_ios_session* s, char* out, int cap);
// Soak sessions: the report (soak numbers, then the stream facts); capture is stopped afterwards, call intono_ios_stop next.
int intono_ios_finish_soak(intono_ios_session* s, char* out, int cap);
// 1 if the current output route is headphone-like (wired, Bluetooth A2DP/HFP/LE, USB).
int intono_ios_headphones(void);
// Engine create / process a generated tone / read / destroy, no audio device. 1 on success.
int intono_ios_smoke(void);
// Keeps the C API Dart looks up with dlsym from being dead-stripped; returns how many of its functions are linked (9 expected).
int intono_ios_link_c_api(void);

#ifdef __cplusplus
}
#endif
#endif
