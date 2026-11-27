#include "soak.hpp"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <ctime>

#include "engine_internal.hpp"

namespace intono_shim {

double slope_per_minute(const std::vector<double>& y) {
  const size_t n = y.size();
  if (n < 2) return 0.0;
  double sx = 0, sy = 0, sxx = 0, sxy = 0;
  for (size_t i = 0; i < n; ++i) {
    const double x = static_cast<double>(i) / 60.0;   // minutes
    sx += x;
    sy += y[i];
    sxx += x * x;
    sxy += x * y[i];
  }
  const double d = static_cast<double>(n) * sxx - sx * sx;
  return d == 0.0 ? 0.0 : (static_cast<double>(n) * sxy - sx * sy) / d;
}

double cpu_share_percent(double cpu_s, double wall_s) { return wall_s > 0.0 ? 100.0 * cpu_s / wall_s : 0.0; }

std::string SoakResult::text() const {
  char b[256];
  std::string t;
  std::snprintf(b, sizeof b, "soak (%s): %.1f min, %d Hz\n", worker ? "worker thread" : "inline, no worker: battery baseline", wall_s / 60.0,
                sample_rate);
  t += b;
  if (planned_s > 0.0 && wall_s + 1.0 < planned_s) {
    std::snprintf(b, sizeof b, "stopped early: %.1f of %.1f min\n", wall_s / 60.0, planned_s / 60.0);
    t += b;
  }
  if (worker) {
    std::snprintf(b, sizeof b, "W3 queue: high-water %zu records (desktop cap 64), slope %+.3f records/min (cap 1), dropped %llu, %zu s sampled\n",
                  high_water, slope, static_cast<unsigned long long>(dropped), seconds_sampled);
    t += b;
    std::snprintf(b, sizeof b, "W4 worker latency: mean %.2f ms, p99 %.2f ms (desktop cap 10 ms), max %.2f ms over %zu records\n",
                  latency_mean_us / 1000.0, latency_p99_us / 1000.0, latency_max_us / 1000.0, probe_n);
    t += b;
    std::snprintf(b, sizeof b, "worker cost per record: mean %.2f us, max %.1f us\n", work_mean_us, work_max_us);
    t += b;
  }
  std::snprintf(b, sizeof b, "process CPU %.1f s in %.1f s = %.2f%% of one core\n", cpu_s, wall_s, cpu_share_percent(cpu_s, wall_s));
  t += b;
  return t;
}

SoakMonitor::SoakMonitor(intono_engine* e, bool worker, int sample_rate) : e_(e), worker_(worker), sample_rate_(sample_rate) {
  per_second_max_.reserve(2 * 3600);
  if (worker_ && e_) intono_internal::reset_queue_high_water(e_);
}

SoakMonitor::~SoakMonitor() { stop_sampler(); }

void SoakMonitor::sample() {
  std::lock_guard<std::mutex> l(mu_);
  size_t hw = 0;
  if (worker_ && e_) {
    hw = intono_internal::queue_high_water(e_);
    intono_internal::reset_queue_high_water(e_);
  }
  per_second_max_.push_back(static_cast<double>(hw));
  high_water_ = std::max(high_water_, hw);
}

void SoakMonitor::start_sampler(int period_ms) {
  stop_sampler();
  stop_.store(false);
  sampler_ = std::thread([this, period_ms] {
    auto next = std::chrono::steady_clock::now();
    while (!stop_.load()) {
      next += std::chrono::milliseconds(period_ms);
      while (!stop_.load() && std::chrono::steady_clock::now() < next) std::this_thread::sleep_for(std::chrono::milliseconds(5));
      if (stop_.load()) break;
      sample();
    }
  });
}

void SoakMonitor::stop_sampler() {
  stop_.store(true);
  if (sampler_.joinable()) sampler_.join();
}

size_t SoakMonitor::seconds_sampled() const {
  std::lock_guard<std::mutex> l(mu_);
  return per_second_max_.size();
}

std::string SoakMonitor::status() const {
  std::lock_guard<std::mutex> l(mu_);
  char b[160];
  const unsigned long long dropped = (worker_ && e_) ? static_cast<unsigned long long>(intono_internal::dropped_records(e_)) : 0ULL;
  std::snprintf(b, sizeof b, "%zu s, queue high-water %zu, dropped %llu", per_second_max_.size(), high_water_, dropped);
  return b;
}

SoakResult SoakMonitor::finish(double wall_s, double cpu_s, double planned_s) {
  stop_sampler();
  SoakResult r;
  r.worker = worker_;
  r.sample_rate = sample_rate_;
  r.wall_s = wall_s;
  r.cpu_s = cpu_s;
  r.planned_s = planned_s;
  {
    std::lock_guard<std::mutex> l(mu_);
    r.seconds_sampled = per_second_max_.size();
    r.high_water = high_water_;
    r.slope = slope_per_minute(per_second_max_);
  }
  if (worker_ && e_) {
    const intono_internal::ProbeStats ps = intono_internal::probe_stats(e_);   // drains the worker
    r.dropped = intono_internal::dropped_records(e_);
    r.probe_n = ps.n;
    r.latency_mean_us = ps.latency_mean_us;
    r.latency_p99_us = ps.latency_p99_us;
    r.latency_max_us = ps.latency_max_us;
    r.work_mean_us = ps.work_mean_us;
    r.work_max_us = ps.work_max_us;
  }
  return r;
}

double process_cpu_seconds() {
  timespec ts{};
  clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts);
  return static_cast<double>(ts.tv_sec) + ts.tv_nsec * 1e-9;
}

double monotonic_seconds() {
  return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

}  // namespace intono_shim
