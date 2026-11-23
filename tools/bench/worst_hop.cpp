// Per-call timing of intono_process with one hop (256 samples) per call: mean, p99, p99.9, max, and the 10 worst.
//   worst_hop file.wav [reps] [silence_seconds]      env PIN_CORE=n pins the calling (audio) thread; the engine's worker thread is not pinned.
// Uses the product path (worker thread, ADR 0008). Intrinsic cost = per-hop minimum over reps.
#include <algorithm>
#include <numeric>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
#include <pthread.h>
#include <sched.h>
#include "engine_internal.hpp"
#include "intono/intono.h"
static bool read_wav(const char* p, std::vector<float>& x, int& sr) {
  FILE* f = fopen(p, "rb"); if (!f) return false;
  char h[12]; fread(h, 1, 12, f); int16_t fmt = 0, ch = 0, bits = 0; std::vector<unsigned char> data;
  for (;;) { char id[4]; uint32_t n; if (fread(id, 1, 4, f) != 4 || fread(&n, 4, 1, f) != 1) break;
    if (!memcmp(id, "fmt ", 4)) { std::vector<unsigned char> b(n); fread(b.data(), 1, n, f); memcpy(&fmt, &b[0], 2); memcpy(&ch, &b[2], 2); uint32_t s; memcpy(&s, &b[4], 4); sr = (int)s; memcpy(&bits, &b[14], 2); }
    else if (!memcmp(id, "data", 4)) { data.resize(n); fread(data.data(), 1, n, f); break; }
    else fseek(f, n + (n & 1), SEEK_CUR); }
  fclose(f);
  if (bits == 16 && ch >= 1) { size_t m = data.size() / (2 * ch); x.resize(m); for (size_t i = 0; i < m; ++i) { int16_t v; memcpy(&v, &data[i * 2 * ch], 2); x[i] = v / 32768.f; } return true; }
  if (bits == 32 && fmt == 3) { size_t m = data.size() / (4 * ch); x.resize(m); for (size_t i = 0; i < m; ++i) memcpy(&x[i], &data[i * 4 * ch], 4); return true; }
  return false;
}
int main(int argc, char** argv) {
  std::vector<float> x; int sr = 48000; if (argc < 2 || !read_wav(argv[1], x, sr)) { fprintf(stderr, "wav?\n"); return 1; }
  int reps = argc > 2 ? atoi(argv[2]) : 3;
  double pad_s = argc > 3 ? atof(argv[3]) : 0.25;   // digital silence appended after the file (long values expose denormals)
  intono_config c{}; c.sample_rate = (float)sr; c.window_size = 1024; c.hop_size = 256; c.a4_hz = 440; c.tuning = 0; c.min_hz = 180; c.max_hz = 3200;
  std::vector<std::vector<double>> per;
  for (int r = 0; r < reps; ++r) {
    per.emplace_back();
    intono_engine* e = intono_internal::create(&c, getenv("INLINE") != nullptr);   // INLINE=1: the tracker runs on the calling thread (pre-ADR 0008 path)
    if (const char* pc = getenv("PIN_CORE")) { cpu_set_t cs; CPU_ZERO(&cs); CPU_SET(atoi(pc), &cs); pthread_setaffinity_np(pthread_self(), sizeof cs, &cs); }
    std::vector<intono_note> nb(64); std::vector<intono_frame> fb(1024);
    std::vector<float> pad((size_t)(sr * pad_s), 0.f);
    auto feed = [&](const std::vector<float>& v) {
      for (size_t i = 0; i + 256 <= v.size(); i += 256) {
        auto t0 = std::chrono::steady_clock::now(); intono_process(e, &v[i], 256); auto t1 = std::chrono::steady_clock::now();
        if (r > 0) per.back().push_back(std::chrono::duration<double, std::micro>(t1 - t0).count());
        if ((i / 256) % 64 == 0) { intono_read_frames(e, fb.data(), 1024); intono_read_notes(e, nb.data(), 64); }
      } };
    feed(x); feed(pad); intono_destroy(e);
  }
  std::vector<double> mins, us;
  size_t n = per[1].size();
  for (size_t i = 0; i < n; ++i) { double m = 1e18; for (size_t r = 1; r < per.size(); ++r) if (i < per[r].size()) { m = std::min(m, per[r][i]); us.push_back(per[r][i]); } mins.push_back(m); }
  { std::vector<double> t = mins; std::sort(t.begin(), t.end()); printf("per-hop MIN over %zu reps (intrinsic cost): mean %.1f p99 %.1f p99.9 %.1f max %.1f us; top5:", per.size() - 1, std::accumulate(t.begin(), t.end(), 0.0) / t.size(), t[(size_t)(.99 * t.size())], t[(size_t)(.999 * t.size())], t.back()); for (int i = 1; i <= 5; ++i) printf(" %.0f", t[t.size() - i]); printf("\n"); }
  { std::vector<size_t> idx; for (size_t i = 0; i < mins.size(); ++i) if (mins[i] > 100) idx.push_back(i); printf("hops over 100us (min over reps): %zu of %zu; first indices:", idx.size(), mins.size()); for (size_t k = 0; k < idx.size() && k < 24; ++k) printf(" %zu", idx[k]); printf("\n"); }
  std::vector<double> s = us; std::sort(s.begin(), s.end()); double sum = 0; for (double v : s) sum += v;
  auto q = [&](double p) { return s[std::min(s.size() - 1, (size_t)(p * s.size()))]; };
  printf("%s: hops %zu mean %.1f p50 %.1f p99 %.1f p99.9 %.1f max %.1f us; worst5:", argv[1], s.size(), sum / s.size(), q(.5), q(.99), q(.999), s.back());
  for (int i = 1; i <= 5; ++i) printf(" %.0f", s[s.size() - i]); printf("\n");
}
