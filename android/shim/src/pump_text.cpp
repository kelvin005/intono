#include "pump_text.hpp"

#include <cstdio>
#include <vector>

namespace intono_shim {

std::string pump_text(const AudioPump& pump) {
  char buf[512];
  std::string s;
  const PumpStats p = pump.snapshot();
  const auto ull = [](uint64_t v) { return static_cast<unsigned long long>(v); };
  std::snprintf(buf, sizeof buf, "hop us: median %.1f, p99 %.1f, max %.1f (%llu hops); slow (> 1000 us): %llu\ncallback us: max %.1f\n",
                p.chunk.p50_ns / 1e3, p.chunk.p99_ns / 1e3, p.chunk.max_ns / 1e3, ull(p.chunk.count), ull(p.slow_hops), p.callback.max_ns / 1e3);
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
  list("slow hops (t s, us):", pump.events(EventKind::SlowHop), "us");
  list("gaps (t s, frames):", pump.events(EventKind::PositionGap), "f");
  list("overruns (t s, count):", pump.events(EventKind::Overrun), "");
  return s;
}

}  // namespace intono_shim
