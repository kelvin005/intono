cmake_minimum_required(VERSION 3.20)
project(libintono LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

option(INTONO_BUILD_TESTS "Build GoogleTest suite" ON)
option(INTONO_BUILD_CLI "Build intono-cli" ON)
option(INTONO_DENORMAL_GUARD "Software denormal flush (ADR 0008 Amendment 1). OFF only for the bench-mode comparison, never for shipping" ON)
option(INTONO_SHARED "Build libintono as a shared library (Android libintono.so)" OFF)
set(INTONO_SANITIZE "none" CACHE STRING "none, address (ASan+UBSan) or thread (TSan)")

# No -ffast-math anywhere: the C++ core must stay bit-comparable with the Python reference.
set(INTONO_WARN -Wall -Wextra -Wpedantic -Wno-unused-parameter)
if(INTONO_SANITIZE STREQUAL "address")
  set(INTONO_SAN -fsanitize=address,undefined -fno-omit-frame-pointer)
elseif(INTONO_SANITIZE STREQUAL "thread")
  set(INTONO_SAN -fsanitize=thread -fno-omit-frame-pointer)
else()
  set(INTONO_SAN "")
endif()

# ---- pffft (vendored, float only) -------------------------------------------
set(PFFFT ${CMAKE_CURRENT_SOURCE_DIR}/third_party/pffft)
add_library(pffft STATIC ${PFFFT}/src/pffft.c ${PFFFT}/src/pffft_common.c)
target_include_directories(pffft PUBLIC ${PFFFT}/include/pffft PRIVATE ${PFFFT}/src)
target_compile_definitions(pffft PRIVATE _USE_MATH_DEFINES PFFFT_SCALVEC_ENABLED=1 PUBLIC PFFFT_STATIC_DEFINE)
target_compile_options(pffft PRIVATE ${INTONO_SAN})
target_link_libraries(pffft PUBLIC m)
set_target_properties(pffft PROPERTIES C_VISIBILITY_PRESET hidden)

# ---- libintono ----------------------------------------------------------------
if(INTONO_SHARED)
  if(INTONO_BUILD_TESTS)
    message(FATAL_ERROR "INTONO_SHARED=ON needs INTONO_BUILD_TESTS=OFF: the tests use internal headers that a shared build hides")
  endif()
  add_library(intono SHARED src/engine.cpp)
  if(NOT APPLE)
    target_link_options(intono PRIVATE -Wl,--exclude-libs,ALL)   # export only the INTONO_API functions, not pffft or libc++
  endif()
  if(ANDROID)
    target_link_options(intono PRIVATE -Wl,-z,max-page-size=16384)  # Google Play: 16 KB page alignment for Android 15+
  endif()
else()
  add_library(intono STATIC src/engine.cpp)
endif()
target_include_directories(intono PUBLIC include PRIVATE src)
if(INTONO_DENORMAL_GUARD)
  target_compile_definitions(intono PUBLIC INTONO_DENORMAL_GUARD=1)
else()
  message(WARNING "INTONO_DENORMAL_GUARD=OFF: for the bench-mode comparison only, never ship this build")
  target_compile_definitions(intono PUBLIC INTONO_DENORMAL_GUARD=0)
endif()
target_compile_options(intono PRIVATE ${INTONO_WARN} ${INTONO_SAN})
find_package(Threads REQUIRED)
target_link_libraries(intono PUBLIC pffft Threads::Threads)   # the note worker thread (ADR 0008)
if(INTONO_SAN)
  target_link_options(intono PUBLIC ${INTONO_SAN})
endif()

if(INTONO_BUILD_CLI)
  add_executable(intono-cli cli/main.cpp)
  target_include_directories(intono-cli PRIVATE src)   # engine_internal.hpp: inline mode, drain, test hooks (not exported)
  target_link_libraries(intono-cli PRIVATE intono)
  target_compile_options(intono-cli PRIVATE ${INTONO_WARN})
endif()

if(INTONO_BUILD_TESTS)
  include(FetchContent)
  set(INSTALL_GTEST OFF CACHE BOOL "" FORCE)
  FetchContent_Declare(googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG v1.14.0)
  # offline / pinned: -DFETCHCONTENT_SOURCE_DIR_GOOGLETEST=/path/to/googletest
  FetchContent_MakeAvailable(googletest)

  enable_testing()
  add_executable(intono_tests
    tests/test_ringbuffer.cpp tests/test_filters.cpp tests/test_tuning.cpp
    tests/test_pitch.cpp tests/test_engine.cpp tests/test_notes.cpp tests/test_worker.cpp)
  target_include_directories(intono_tests PRIVATE src)
  target_compile_options(intono_tests PRIVATE ${INTONO_WARN} ${INTONO_SAN})
  target_link_libraries(intono_tests PRIVATE intono GTest::gtest_main)
  add_test(NAME intono_tests COMMAND intono_tests)
  # The whole suite again through the worker thread (ADR 0008): same assertions, the product path.
  add_test(NAME intono_tests_threaded COMMAND intono_tests)
  set_tests_properties(intono_tests_threaded PROPERTIES ENVIRONMENT "INTONO_TEST_THREADED=1")

  # Real-time safety: wraps malloc/calloc/realloc/free and pthread_mutex_lock so the test
  # fails if intono_process or intono_drone_render allocates or locks. Not combined with
  # sanitizers (they interpose the same symbols).
  if(NOT INTONO_SAN AND UNIX AND NOT APPLE AND NOT ANDROID)   # glibc symbols: not bionic (ADR 0005)
    add_executable(intono_rt_safety tests/test_rt_safety.cpp)
    target_include_directories(intono_rt_safety PRIVATE src)
    target_compile_options(intono_rt_safety PRIVATE ${INTONO_WARN})
    target_link_libraries(intono_rt_safety PRIVATE intono GTest::gtest)
    target_link_options(intono_rt_safety PRIVATE
      -Wl,--wrap=malloc -Wl,--wrap=calloc -Wl,--wrap=realloc -Wl,--wrap=posix_memalign
      -Wl,--wrap=aligned_alloc -Wl,--wrap=pthread_mutex_lock)
    add_test(NAME intono_rt_safety COMMAND intono_rt_safety)
  endif()
endif()
