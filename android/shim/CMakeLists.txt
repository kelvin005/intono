# Android audio shim (ADR 0009). This directory builds on the host (Linux, macOS) for the AudioPump unit tests, and on Android
# (NDK toolchain) for the shim library once the Oboe layer lands. AudioPump itself has no Android dependency.
cmake_minimum_required(VERSION 3.20)
project(intono_shim LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

option(INTONO_SHIM_BUILD_TESTS "Build the AudioPump tests" ON)
if(ANDROID)
  set(INTONO_SHIM_BUILD_TESTS OFF CACHE BOOL "" FORCE)   # the host tests run on the host; Gradle builds only the library
endif()
set(INTONO_SANITIZE "none" CACHE STRING "none, address (ASan+UBSan) or thread (TSan)")

# libintono, exactly as in Phase 1 (no tests, no CLI from here; same sanitizer choice).
set(INTONO_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(INTONO_BUILD_CLI OFF CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../dsp ${CMAKE_CURRENT_BINARY_DIR}/dsp)

set(SHIM_WARN -Wall -Wextra -Wpedantic -Wno-unused-parameter)
if(INTONO_SANITIZE STREQUAL "address")
  set(SHIM_SAN -fsanitize=address,undefined -fno-omit-frame-pointer)
elseif(INTONO_SANITIZE STREQUAL "thread")
  set(SHIM_SAN -fsanitize=thread -fno-omit-frame-pointer)
else()
  set(SHIM_SAN "")
endif()

add_library(intono_shim_core STATIC src/audio_pump.cpp src/bench.cpp)
target_include_directories(intono_shim_core PUBLIC src)
target_compile_options(intono_shim_core PRIVATE ${SHIM_WARN} ${SHIM_SAN})
target_link_libraries(intono_shim_core PUBLIC intono)
if(SHIM_SAN)
  target_link_options(intono_shim_core PUBLIC ${SHIM_SAN})
endif()

# ---- Bench comparison library: libintono with the denormal guard OFF + the bench entry point (ADR 0009 answer 4) ----------------------
# Information only, shipped in the bench APK and never in a release: it exports intono_bench_run and nothing else.
option(INTONO_BENCH_NOGUARD "Also build libintono_bench_noguard (guard OFF) for the bench-mode comparison" OFF)
if(INTONO_BENCH_NOGUARD)
  find_package(Threads REQUIRED)
  set(INTONO_DSP_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../dsp)
  add_library(intono_noguard STATIC ${INTONO_DSP_DIR}/src/engine.cpp)
  target_include_directories(intono_noguard PUBLIC ${INTONO_DSP_DIR}/include PRIVATE ${INTONO_DSP_DIR}/src)
  target_compile_definitions(intono_noguard PUBLIC INTONO_DENORMAL_GUARD=0)
  target_compile_options(intono_noguard PRIVATE ${SHIM_WARN} ${SHIM_SAN})
  target_link_libraries(intono_noguard PUBLIC pffft Threads::Threads)
  add_library(intono_bench_noguard SHARED src/bench.cpp)
  target_include_directories(intono_bench_noguard PRIVATE src)
  target_compile_options(intono_bench_noguard PRIVATE ${SHIM_WARN} ${SHIM_SAN})
  target_link_libraries(intono_bench_noguard PRIVATE intono_noguard)
  if(UNIX AND NOT APPLE)
    target_link_options(intono_bench_noguard PRIVATE -Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/bench_exports.map -Wl,--exclude-libs,ALL)
  endif()
  if(ANDROID)
    target_link_options(intono_bench_noguard PRIVATE -Wl,-z,max-page-size=16384)
  endif()
endif()

# ---- Android library: libintono + AudioPump + Oboe streams + JNI (built by Gradle, ADR 0009) -----------------------------------
if(ANDROID)
  find_package(oboe REQUIRED CONFIG)   # Prefab package from Google Maven (shared STL only)
  add_library(intono_android SHARED src/oboe_audio.cpp src/jni_bridge.cpp)
  target_compile_options(intono_android PRIVATE ${SHIM_WARN})
  target_link_libraries(intono_android PRIVATE intono_shim_core oboe::oboe log)
  # libintono is a static archive: keep the whole C API in the library (Dart looks the symbols up with dlsym) and export only
  # intono_*, the JNI entry points and JNI_OnLoad.
  set(INTONO_API_SYMS intono_create intono_process intono_read_frames intono_read_notes intono_set_tonic intono_drone_set
      intono_drone_render intono_destroy)
  foreach(sym ${INTONO_API_SYMS} intono_bench_run)   # intono_bench_run: the bench entry point Dart looks up (ADR 0009 decision 5)
    target_link_options(intono_android PRIVATE -Wl,--undefined=${sym})
  endforeach()
  target_link_options(intono_android PRIVATE
    -Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/exports.map
    -Wl,-z,max-page-size=16384)   # Google Play: 16 KB page alignment for Android 15+
endif()

if(INTONO_SHIM_BUILD_TESTS)
  include(FetchContent)
  set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(googletest GIT_REPOSITORY https://github.com/google/googletest.git GIT_TAG v1.14.0)
  FetchContent_MakeAvailable(googletest)
  enable_testing()

  add_executable(intono_shim_tests tests/test_audio_pump.cpp tests/test_bench.cpp)
  target_compile_options(intono_shim_tests PRIVATE ${SHIM_WARN} ${SHIM_SAN})
  target_link_libraries(intono_shim_tests PRIVATE intono_shim_core GTest::gtest_main)
  add_test(NAME intono_shim_tests COMMAND intono_shim_tests)

  if(INTONO_BENCH_NOGUARD AND UNIX AND NOT APPLE AND NOT ANDROID AND NOT SHIM_SAN)
    add_executable(intono_bench_libs_tests tests/test_bench_libs.cpp)
    target_compile_options(intono_bench_libs_tests PRIVATE ${SHIM_WARN})
    target_compile_definitions(intono_bench_libs_tests PRIVATE INTONO_BENCH_NOGUARD_LIB="$<TARGET_FILE:intono_bench_noguard>")
    target_link_libraries(intono_bench_libs_tests PRIVATE intono_shim_core GTest::gtest_main ${CMAKE_DL_LIBS})
    add_test(NAME intono_bench_libs_tests COMMAND intono_bench_libs_tests)
  endif()

  # Same instrumentation as dsp/tests/test_rt_safety.cpp: fails if the pump allocates or locks on the audio thread.
  if(NOT SHIM_SAN AND UNIX AND NOT APPLE AND NOT ANDROID)
    add_executable(intono_shim_rt_safety tests/test_pump_rt_safety.cpp)
    target_compile_options(intono_shim_rt_safety PRIVATE ${SHIM_WARN})
    target_link_libraries(intono_shim_rt_safety PRIVATE intono_shim_core GTest::gtest)
    target_link_options(intono_shim_rt_safety PRIVATE
      -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc -Wl,--wrap=posix_memalign
      -Wl,--wrap=aligned_alloc -Wl,--wrap=pthread_mutex_lock)
    add_test(NAME intono_shim_rt_safety COMMAND intono_shim_rt_safety)
  endif()
endif()
