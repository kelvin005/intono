// Internal, NOT exported (ADR 0008): used by the CLI, the unit tests and the benchmarks. Not part of the C API.
//
// Inline mode: no worker thread; intono_process runs the note tracker itself, exactly as before ADR 0008. The CLI, the parity tools, the
// sealed-set runners and the unit tests use it so that every certified number stays reproducible. The threaded path is the product.
#pragma once
#include <cstddef>
#include <cstdint>

#include "intono/intono.h"

namespace intono_internal {

// Like intono_create, with the choice of mode. Threaded mode returns nullptr if the worker thread cannot be created.
intono_engine* create(const intono_config* cfg, bool inline_mode);

// Audio-thread (the thread that calls intono_process) only: blocks until the worker has consumed every record pushed so far
// (or the record was dropped). A no-op in inline mode. For tests and tools, never for the product.
void drain(intono_engine* e);

// Records the audio thread could not queue (queue full). The worker ends the run at the hole.
uint64_t dropped_records(const intono_engine* e);
// Queue depth now and the high-water mark since the last reset (sampled by the worker at every pop).
size_t queue_depth(const intono_engine* e);
size_t queue_high_water(const intono_engine* e);
void reset_queue_high_water(intono_engine* e);

// Test hooks for the worker (all off by default): a random sleep of 0..max_us before each record (seeded), and a busy wait per record.
void set_worker_stall(intono_engine* e, int max_us, uint32_t seed);
void set_worker_spin_ns(intono_engine* e, int ns);

// Latency probe: if enabled before the first intono_process, the worker records, per record, the wall time from the push (taken on the
// audio thread) to the end of the tracker call, and the time spent in the tracker. `cap` records at most. Costs one clock read per hop.
void enable_probe(intono_engine* e, size_t cap);
struct ProbeStats {
  size_t n = 0;
  double latency_mean_us = 0, latency_p99_us = 0, latency_max_us = 0;
  double work_mean_us = 0, work_max_us = 0;
};
ProbeStats probe_stats(intono_engine* e);

}  // namespace intono_internal
