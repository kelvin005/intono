// The stream-facts lines of an AudioPump (hop and callback timings, gaps, overruns, xruns, the newest slow hops, gaps and overruns), shared
// by the Android (Oboe) and iOS (AVAudioEngine) shims. Timings and counts only, never audio. Allocates: UI thread only.
#pragma once
#include <string>

#include "audio_pump.hpp"

namespace intono_shim {
std::string pump_text(const AudioPump& p);
}
