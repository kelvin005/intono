// W3 / W4 (ADR 0008): the note worker keeps up over a long stream, and the wall-clock latency of a record through the worker.
//
//   soak file.wav [file2.wav ...] --minutes 30 [--speed 1] [--spin-mult 0] [--pin 1]
//
// Loops the given files into a stream of --minutes, feeds it to the PRODUCT path (worker thread) in hop-sized intono_process calls paced at
// real time x --speed (speed 1 = real time; a call that is already late is not delayed, so at high speed the pace is "as fast as the audio
// thread goes"). --spin-mult K slows the worker by K x its measured mean cost per record (a calibration pass of 60 stream-seconds measures it),
// to emulate a low-end phone. The audio thread is pinned (--pin) so the worker keeps the other core.
// Reports: queue depth high-water mark, least-squares slope of the per-second maximum depth (records per minute), drops, worker latency
// (push -> note tracker done) mean / p99 / max, worker cost per record. W3: high-water <= 64 and slope <= 1 record/min, no drops.
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>
#include <pthread.h>
#include <sched.h>
#include "engine_internal.hpp"
#include "intono/intono.h"

static bool read_wav(const char* p, std::vector<float>& x, int& sr) {
  FILE* f = fopen(p, "rb"); if (!f) return false;
  char h[12]; if (fread(h, 1, 12, f) != 12) return false; int16_t fmt = 0, ch = 0, bits = 0; std::vector<unsigned char> data;
  for (;;) { char id[4]; uint32_t n; if (fread(id, 1, 4, f) != 4 || fread(&n, 4, 1, f) != 1) break;
    if (!memcmp(id, "fmt ", 4)) { std::vector<unsigned char> b(n); if (fread(b.data(), 1, n, f) != n) break; memcpy(&fmt, &b[0], 2); memcpy(&ch, &b[2], 2); uint32_t s; memcpy(&s, &b[4], 4); sr = (int)s; memcpy(&bits, &b[14], 2); }
    else if (!memcmp(id, "data", 4)) { data.resize(n); if (fread(data.data(), 1, n, f) != n) break; break; }
    else fseek(f, n + (n & 1), SEEK_CUR); }
  fclose(f);
  if (bits == 16 && ch >= 1) { size_t m = data.size() / (2 * ch); x.resize(m); for (size_t i = 0; i < m; ++i) { int16_t v; memcpy(&v, &data[i * 2 * ch], 2); x[i] = v / 32768.f; } return true; }
  if (bits == 32 && fmt == 3) { size_t m = data.size() / (4 * ch); x.resize(m); for (size_t i = 0; i < m; ++i) memcpy(&x[i], &data[i * 4 * ch], 4); return true; }
  return false;
}

struct Result { size_t high = 0; double slope = 0; uint64_t dropped = 0; intono_internal::ProbeStats ps; size_t notes = 0, hops = 0; double wall_s = 0; };

static Result run(const std::vector<float>& src, int sr, double stream_s, double speed, int spin_ns, int pin) {
  intono_config c{}; c.sample_rate = (float)sr; c.window_size = 1024; c.hop_size = 256; c.a4_hz = 440; c.tuning = 0; c.min_hz = 180; c.max_hz = 3200;
  intono_engine* e = intono_create(&c);
  if (!e) { fprintf(stderr, "create failed\n"); exit(1); }
  if (pin >= 0) { cpu_set_t cs; CPU_ZERO(&cs); CPU_SET(pin, &cs); pthread_setaffinity_np(pthread_self(), sizeof cs, &cs); }
  const size_t hops = (size_t)(stream_s * sr / 256);
  intono_internal::enable_probe(e, hops + 16);
  if (spin_ns > 0) intono_internal::set_worker_spin_ns(e, spin_ns);
  std::vector<intono_note> nb(64); std::vector<intono_frame> fb(256);
  std::vector<double> per_sec_max; double cur_max = 0; size_t hops_per_s = (size_t)(sr / 256.0 + 0.5);
  const auto t0 = std::chrono::steady_clock::now(); const double hop_s = 256.0 / sr / speed;
  size_t pos = 0, notes = 0;
  for (size_t k = 0; k < hops; ++k) {
    if (speed < 1e6) std::this_thread::sleep_until(t0 + std::chrono::duration_cast<std::chrono::steady_clock::duration>(std::chrono::duration<double>(k * hop_s)));
    if (pos + 256 > src.size()) pos = 0;
    intono_process(e, src.data() + pos, 256); pos += 256;
    cur_max = std::max(cur_max, (double)intono_internal::queue_depth(e));
    if ((k + 1) % hops_per_s == 0) { per_sec_max.push_back(cur_max); cur_max = 0; }
    if (k % 32 == 0) { intono_read_frames(e, fb.data(), 256); int g; while ((g = intono_read_notes(e, nb.data(), 64)) > 0) notes += g; }
  }
  const double wall = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  Result r; r.hops = hops; r.wall_s = wall;
  r.ps = intono_internal::probe_stats(e);   // drains
  { int g; while ((g = intono_read_notes(e, nb.data(), 64)) > 0) notes += g; }
  r.notes = notes; r.high = intono_internal::queue_high_water(e); r.dropped = intono_internal::dropped_records(e);
  const size_t n = per_sec_max.size();   // least squares: depth against minutes
  if (n > 2) { double sx = 0, sy = 0, sxx = 0, sxy = 0; for (size_t i = 0; i < n; ++i) { double x = i / 60.0, y = per_sec_max[i]; sx += x; sy += y; sxx += x * x; sxy += x * y; } r.slope = (n * sxy - sx * sy) / (n * sxx - sx * sx); }
  intono_destroy(e);
  return r;
}

int main(int argc, char** argv) {
  std::vector<std::string> files; double minutes = 30, speed = 1, spin_mult = 0; int pin = -1;
  for (int i = 1; i < argc; ++i) { std::string a = argv[i];
    if (a == "--minutes" && i + 1 < argc) minutes = atof(argv[++i]); else if (a == "--speed" && i + 1 < argc) speed = atof(argv[++i]);
    else if (a == "--spin-mult" && i + 1 < argc) spin_mult = atof(argv[++i]); else if (a == "--pin" && i + 1 < argc) pin = atoi(argv[++i]);
    else files.push_back(a); }
  std::vector<float> src; int sr = 48000;
  for (auto& f : files) { std::vector<float> x; int s = 0; if (!read_wav(f.c_str(), x, s)) { fprintf(stderr, "wav? %s\n", f.c_str()); return 1; } if (src.empty()) sr = s; if (s != sr) { fprintf(stderr, "mixed sample rates\n"); return 1; } src.insert(src.end(), x.begin(), x.end()); }
  if (src.size() < 4096) { fprintf(stderr, "need audio\n"); return 1; }
  int spin_ns = 0;
  if (spin_mult > 0) {
    Result cal = run(src, sr, 60, 1e9, 0, pin);
    spin_ns = (int)(spin_mult * cal.ps.work_mean_us * 1000.0);
    printf("calibration: worker mean cost %.2f us per record (max %.1f); slowing the worker by x%.1f = +%d ns per record\n", cal.ps.work_mean_us, cal.ps.work_max_us, spin_mult, spin_ns);
  }
  Result r = run(src, sr, minutes * 60.0, speed, spin_ns, pin);
  printf("stream %.1f min in %.1f s wall (speed x%.0f), %zu records, %zu notes\n", minutes, r.wall_s, speed, r.hops, r.notes);
  printf("W3 queue: high-water %zu records (cap 64), slope %+.3f records/min (cap 1), dropped %llu: %s\n", r.high, r.slope, (unsigned long long)r.dropped,
         (r.high <= 64 && r.slope <= 1.0 && r.dropped == 0) ? "PASS" : "FAIL");
  printf("W4 worker latency (push -> tracker done): mean %.1f us, p99 %.1f us, max %.1f us (cap p99 10 ms); worker cost per record: mean %.2f us, max %.1f us\n",
         r.ps.latency_mean_us, r.ps.latency_p99_us, r.ps.latency_max_us, r.ps.work_mean_us, r.ps.work_max_us);
  return 0;
}
