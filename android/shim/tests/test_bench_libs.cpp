// The two builds of the engine that bench mode compares (ADR 0009 answer 4): the shim's own (guard ON, the default) and
// libintono_bench_noguard (guard OFF, shipped only in the bench APK). Loaded side by side exactly as the app does, with dlopen.
#include <dlfcn.h>
#include <gtest/gtest.h>

#include <string>

#include "bench.hpp"

namespace {
using BenchFn = int (*)(int, char*, int);

std::string run_from(void* lib, int runs) {
  auto fn = reinterpret_cast<BenchFn>(dlsym(lib, "intono_bench_run"));
  EXPECT_NE(fn, nullptr) << dlerror();
  if (!fn) return "";
  char buf[4096] = {};
  EXPECT_GT(fn(runs, buf, sizeof buf), 0);
  return buf;
}
}  // namespace

TEST(BenchLibs, TheComparisonLibraryIsTheSameBenchWithTheGuardOff) {
  void* lib = dlopen(INTONO_BENCH_NOGUARD_LIB, RTLD_NOW | RTLD_LOCAL);
  ASSERT_NE(lib, nullptr) << dlerror();
  const std::string off = run_from(lib, 2);
  EXPECT_NE(off.find("guard OFF"), std::string::npos) << off;
  EXPECT_NE(off.find("2 runs x 2437 hops"), std::string::npos) << off;

  char buf[4096] = {};
  ASSERT_GT(intono_bench_run(2, buf, sizeof buf), 0);   // this process's own engine: the default build
  const std::string on = buf;
  EXPECT_NE(on.find("guard ON"), std::string::npos) << on;
  dlclose(lib);
}

TEST(BenchLibs, TheComparisonLibraryExportsOnlyTheBenchEntryPoint) {
  void* lib = dlopen(INTONO_BENCH_NOGUARD_LIB, RTLD_NOW | RTLD_LOCAL);
  ASSERT_NE(lib, nullptr) << dlerror();
  EXPECT_NE(dlsym(lib, "intono_bench_run"), nullptr);
  EXPECT_EQ(dlsym(lib, "intono_create"), nullptr);   // the unguarded engine must not be mistakable for the product engine
  EXPECT_EQ(dlsym(lib, "intono_process"), nullptr);
  dlclose(lib);
}
