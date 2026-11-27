// pump_text (the stream-facts lines shared by the Android and iOS shims): written before the implementation.
#include <gtest/gtest.h>

#include <string>
#include <vector>

#include "audio_pump.hpp"
#include "pump_text.hpp"

using namespace intono_shim;

namespace {
int64_t g_now = 0;
int64_t fake_now(void*) { return g_now; }
void fake_process(void*, const float*, int) { g_now += 2000000; }   // every chunk costs 2 ms: a slow hop
void fake_drone(void*, float*, int) {}
}  // namespace

TEST(PumpText, NamesTheTimingGapAndXrunLines) {
  PumpConfig cfg;
  AudioPump p(EngineOps{nullptr, &fake_process, &fake_drone}, cfg, Clock{nullptr, &fake_now});
  std::vector<float> x(256, 0.f);
  InputInfo info;
  info.position = 0;
  p.on_input(x.data(), 256, info);
  info.position = 256;
  p.on_input(x.data(), 256, info);
  const std::string t = pump_text(p);
  EXPECT_NE(t.find("hop us: median"), std::string::npos) << t;
  EXPECT_NE(t.find("(2 hops); slow (> 1000 us): 2"), std::string::npos) << t;
  EXPECT_NE(t.find("input gaps (stream position): 0, 0 frames lost"), std::string::npos) << t;
  EXPECT_NE(t.find("output xruns 0"), std::string::npos) << t;
  EXPECT_NE(t.find("slow hops (t s, us):"), std::string::npos) << t;
}
