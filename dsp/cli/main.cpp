// intono-cli: run libintono offline over a WAV file and print one CSV row per frame.
//
//   intono-cli file.wav [--a4 440] [--tuning 0|1|2] [--tonic 60] [--chunk 128]
//                       [--min-hz 180] [--max-hz 3200] [--bench N] [--notes 1] [--threaded 1 [--stall US]]
//
// Output columns: t_sec,hz,confidence,midi_note,cents,vib_rate_hz,vib_width_cents,voiced,onset
// --notes 1 prints one CSV row per note (t_start,t_end,midi_note,mean_cents,std_cents,vib_rate_hz,vib_width_cents,
// mean_confidence,frame_count,emit_t) instead of frames, after appending 0.2 s of silence so the last note closes.
// --threaded 1 runs the product path (worker thread, ADR 0008) and waits for the worker after every chunk, so the output, emit_t
// included, must be identical to the default inline mode; --stall US injects random worker stalls of 0..US microseconds.
// --bench N processes the file N times and prints "bench: <us per hop> us/hop" to stderr.
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <sstream>
#include <vector>

#include "engine_internal.hpp"
#include "intono/intono.h"

namespace {

struct Wav {
  int sample_rate = 0;
  std::vector<float> mono;
};

bool read_wav(const char* path, Wav& w) {
  FILE* f = std::fopen(path, "rb");
  if (!f) return false;
  std::vector<unsigned char> d;
  unsigned char buf[65536];
  size_t n;
  while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) d.insert(d.end(), buf, buf + n);
  std::fclose(f);
  auto u16 = [&](size_t o) { return static_cast<int>(d[o] | (d[o + 1] << 8)); };
  auto u32 = [&](size_t o) { return static_cast<uint32_t>(d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (static_cast<uint32_t>(d[o + 3]) << 24)); };
  if (d.size() < 44 || std::memcmp(d.data(), "RIFF", 4) || std::memcmp(d.data() + 8, "WAVE", 4)) return false;
  int fmt = 0, ch = 1, bits = 16;
  size_t pos = 12, data_off = 0, data_len = 0;
  while (pos + 8 <= d.size()) {
    const uint32_t len = u32(pos + 4);
    if (!std::memcmp(d.data() + pos, "fmt ", 4)) {
      fmt = u16(pos + 8);
      ch = u16(pos + 10);
      w.sample_rate = static_cast<int>(u32(pos + 12));
      bits = u16(pos + 22);
      if (fmt == 0xFFFE && len >= 26) fmt = u16(pos + 32);  // WAVE_FORMAT_EXTENSIBLE sub-format
    } else if (!std::memcmp(d.data() + pos, "data", 4)) {
      data_off = pos + 8;
      data_len = std::min<size_t>(len, d.size() - data_off);
      break;
    }
    pos += 8 + len + (len & 1);
  }
  if (!data_off || ch < 1) return false;
  const int bytes = bits / 8;
  const size_t frames = data_len / (static_cast<size_t>(bytes) * ch);
  w.mono.resize(frames);
  for (size_t i = 0; i < frames; ++i) {
    double acc = 0.0;
    for (int c = 0; c < ch; ++c) {
      const unsigned char* p = d.data() + data_off + (i * ch + c) * bytes;
      double v;
      if (fmt == 3 && bits == 32) { float x; std::memcpy(&x, p, 4); v = x; }
      else if (fmt == 1 && bits == 16) v = static_cast<int16_t>(p[0] | (p[1] << 8)) / 32768.0;
      else if (fmt == 1 && bits == 24) v = (static_cast<int32_t>((p[0] << 8) | (p[1] << 16) | (static_cast<uint32_t>(p[2]) << 24)) >> 8) / 8388608.0;
      else if (fmt == 1 && bits == 32) { int32_t x; std::memcpy(&x, p, 4); v = x / 2147483648.0; }
      else return false;
      acc += v;
    }
    w.mono[i] = static_cast<float>(acc / ch);
  }
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::fprintf(stderr, "usage: %s file.wav [--a4 Hz] [--tuning 0|1|2] [--tonic midi] [--chunk n] [--min-hz Hz] [--max-hz Hz] [--bench N] [--notes 1] [--expected m,m,...]\n", argv[0]);
    return 2;
  }
  intono_config cfg{};
  cfg.window_size = 1024; cfg.hop_size = 256; cfg.a4_hz = 440.f; cfg.tuning = 0; cfg.min_hz = 180.f; cfg.max_hz = 3200.f;
  int tonic = 60, chunk = 128, bench = 0;
  bool notes_mode = false, threaded = false;
  int stall_us = 0;
  std::vector<int> expected;
  for (int i = 2; i + 1 < argc; i += 2) {
    const std::string k = argv[i];
    const char* v = argv[i + 1];
    if (k == "--a4") cfg.a4_hz = static_cast<float>(std::atof(v));
    else if (k == "--tuning") cfg.tuning = std::atoi(v);
    else if (k == "--tonic") tonic = std::atoi(v);
    else if (k == "--chunk") chunk = std::max(1, std::atoi(v));
    else if (k == "--min-hz") cfg.min_hz = static_cast<float>(std::atof(v));
    else if (k == "--max-hz") cfg.max_hz = static_cast<float>(std::atof(v));
    else if (k == "--bench") bench = std::atoi(v);
    else if (k == "--notes") notes_mode = std::atoi(v) != 0;
    else if (k == "--threaded") threaded = std::atoi(v) != 0;
    else if (k == "--stall") stall_us = std::atoi(v);
    else if (k == "--expected") {   // scale mode (ADR 0014): comma-separated MIDI numbers
      std::stringstream ss(v);
      std::string tok;
      while (std::getline(ss, tok, ',')) if (!tok.empty()) expected.push_back(std::atoi(tok.c_str()));
    }
    else { std::fprintf(stderr, "unknown option %s\n", k.c_str()); return 2; }
  }
  Wav w;
  if (!read_wav(argv[1], w)) { std::fprintf(stderr, "cannot read %s (need PCM16/24/32 or float32 WAV)\n", argv[1]); return 1; }
  cfg.sample_rate = static_cast<float>(w.sample_rate);

  intono_engine* e = intono_internal::create(&cfg, !threaded);
  if (e && stall_us > 0) intono_internal::set_worker_stall(e, stall_us, 12345u);
  if (!e) { std::fprintf(stderr, "invalid configuration\n"); return 1; }
  intono_set_tonic(e, tonic);
  if (!expected.empty()) intono_set_expected(e, expected.data(), static_cast<int>(expected.size()));

  if (notes_mode) w.mono.resize(w.mono.size() + static_cast<size_t>(0.2 * w.sample_rate), 0.f);  // lets the last note close
  std::vector<intono_frame> out(256);
  std::vector<intono_note> nout(64);
  auto run_once = [&](bool print) {
    for (size_t pos = 0; pos < w.mono.size(); pos += chunk) {
      const int n = static_cast<int>(std::min<size_t>(chunk, w.mono.size() - pos));
      intono_process(e, w.mono.data() + pos, n);
      intono_internal::drain(e);   // no-op inline
      const double emit_t = static_cast<double>(pos + n) / w.sample_rate;  // stream time when the note was read (CLI only)
      int got;
      while ((got = intono_read_notes(e, nout.data(), static_cast<int>(nout.size()))) > 0) {
        if (!print || !notes_mode) continue;
        for (int i = 0; i < got; ++i) {
          const intono_note& q = nout[i];
          std::printf("%.6f,%.6f,%d,%.3f,%.3f,%.3f,%.3f,%.4f,%d,%.6f\n", q.t_start, q.t_end, q.midi_note, q.mean_cents, q.std_cents,
                      q.vibrato_rate_hz, q.vibrato_width_cents, q.mean_confidence, q.frame_count, emit_t);
        }
      }
      while ((got = intono_read_frames(e, out.data(), static_cast<int>(out.size()))) > 0) {
        if (!print || notes_mode) continue;
        for (int i = 0; i < got; ++i) {
          const intono_frame& f = out[i];
          std::printf("%.6f,%.4f,%.4f,%d,%.3f,%.3f,%.3f,%d,%d\n", f.t_sec, f.hz, f.confidence, f.midi_note, f.cents,
                      f.vibrato_rate_hz, f.vibrato_width_cents, f.is_voiced, f.is_onset);
        }
      }
    }
  };

  if (bench > 0) {
    const double hops = static_cast<double>(w.mono.size()) / cfg.hop_size * bench;
    const auto t0 = std::chrono::steady_clock::now();
    for (int r = 0; r < bench; ++r) run_once(false);
    const double us = std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - t0).count();
    std::fprintf(stderr, "bench: %.2f us/hop (hop budget %.0f us, %.2f%% of one core)\n", us / hops,
                 1e6 * cfg.hop_size / cfg.sample_rate, 100.0 * us / hops / (1e6 * cfg.hop_size / cfg.sample_rate));
  } else {
    if (notes_mode) std::printf("t_start,t_end,midi_note,mean_cents,std_cents,vib_rate_hz,vib_width_cents,mean_confidence,frame_count,emit_t\n");
    else std::printf("t_sec,hz,confidence,midi_note,cents,vib_rate_hz,vib_width_cents,voiced,onset\n");
    run_once(true);
  }
  intono_destroy(e);
  return 0;
}
