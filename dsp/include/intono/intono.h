/* libintono public C API: the stable FFI boundary.
 *
 * This header is a contract (architecture doc, "DSP core C API"): change it only
 * with an ADR. Thread rules:
 *   intono_create / intono_destroy                       any thread, not real-time
 *   intono_process, intono_drone_render                  audio thread only, real-time safe
 *   intono_read_frames, intono_read_notes                UI thread only
 *   intono_set_tonic, intono_drone_set                   UI thread (atomics, safe against the audio thread)
 * Notes (ADR 0008): the engine owns one worker thread, started by intono_create and joined by intono_destroy. It runs the
 * note tracker, so a note may be readable a few milliseconds after the audio-time it is stamped with. The audio thread
 * only queues one small record per hop. No function, struct or field changed.
 */
#ifndef INTONO_H
#define INTONO_H

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define INTONO_API __declspec(dllexport)
#else
#define INTONO_API __attribute__((visibility("default")))
#endif

typedef struct intono_engine intono_engine;

typedef struct {
  float sample_rate;      // e.g. 48000
  int   window_size;      // 1024
  int   hop_size;         // 256
  float a4_hz;            // 440.0
  int   tuning;           // 0 = ET, 1 = just, 2 = pythagorean
  float min_hz, max_hz;   // 180, 3200
} intono_config;

typedef struct {
  double t_sec;
  float  hz, confidence;
  int    midi_note;
  float  cents;           // vs target in current tuning
  float  vibrato_rate_hz, vibrato_width_cents;
  int    is_voiced, is_onset;
} intono_frame;

/* One summary per played note (ADR 0003). Times are window-centre times of the first and last voiced frame. */
typedef struct {
  double t_start, t_end;           // seconds
  int    midi_note;                // nearest target of the configured tuning, for the mean pitch
  float  mean_cents;               // whole-note mean of the raw pitch vs that target
  float  std_cents;                // population std of the raw pitch over the note
  float  vibrato_rate_hz;          // mean over frames with a vibrato reading; 0 if under 30% of frames had one
  float  vibrato_width_cents;      // same rule
  float  mean_confidence;          // mean YIN confidence of the voiced frames
  int    frame_count;              // voiced frames in the note
} intono_note;

INTONO_API intono_engine* intono_create(const intono_config* cfg);   // allocates everything and starts the note worker thread; NULL if cfg invalid or the thread cannot be created
INTONO_API void  intono_process(intono_engine*, const float* in, int n);  // audio thread, RT-safe
INTONO_API int   intono_read_frames(intono_engine*, intono_frame* out, int max); // UI thread
INTONO_API int   intono_read_notes(intono_engine*, intono_note* out, int max);   // UI thread
INTONO_API void  intono_set_tonic(intono_engine*, int midi_note);       // for just/pythagorean
INTONO_API void  intono_drone_set(intono_engine*, int midi_note, float gain, int timbre);
INTONO_API void  intono_drone_render(intono_engine*, float* out, int n); // audio thread, RT-safe
INTONO_API void  intono_destroy(intono_engine*);

/* Semantics the struct comments leave open (documented here, not new API):
 *  - intono_frame.hz is the DISPLAYED pitch (vibrato centre, ADR 0001), 0 when unvoiced.
 *  - intono_frame.t_sec is the centre time of the analysis window.
 *  - cents is relative to the nearest target note of the configured tuning; for just and
 *    pythagorean the targets are the scale ratios above the tonic (intono_set_tonic).
 *  - midi_note is the ET note number of that target (for display), 0 when unvoiced.
 *  - Notes are emitted when they END. A note that ends in a pitch change is reported about 213 ms (a fixed-lag
 *    note HMM, ADR 0004) plus the HMM's switch delay after the change (at most ~330 ms measured, limit 350), timestamped at the
 *    change; one that ends in an RMS onset when that frame is final; one that ends in a phrase end once the pitch
 *    has been unvoiced for more than 20 frames (~107 ms). There is no flush call; to read the final note of a
 *    recording, feed ~120 ms of silence. Notes under 10 voiced frames (~53 ms) are discarded. The note mean leaves
 *    out a 30 ms guard zone at each boundary (ADR 0004). Notes are on their own ring (64 entries); if the UI
 *    stops reading, the newest notes are dropped, never the audio thread blocked.
 *  - drone timbre: 0 = sine, 1 = rich (8 harmonics).
 */

#ifdef __cplusplus
}
#endif

#endif /* INTONO_H */
