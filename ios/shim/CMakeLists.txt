# iOS audio shim (ADR 0010): libintono + the portable core shared with Android (android/shim/src: AudioPump, bench, soak, pump_text) + the
# AVAudioEngine session (src/intono_ios.mm). Built for the device and the Simulator by build_xcframework.sh, merged into one static library
# per slice and packaged as IntonoNative.xcframework (headers: intono_ios.h + module.modulemap for Swift).
cmake_minimum_required(VERSION 3.20)
project(intono_ios_shim LANGUAGES C CXX OBJCXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 20)

set(INTONO_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(INTONO_BUILD_CLI OFF CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../../dsp ${CMAKE_CURRENT_BINARY_DIR}/dsp)

set(PORTABLE ${CMAKE_CURRENT_SOURCE_DIR}/../../android/shim/src)
add_library(intono_ios_shim STATIC
  src/intono_ios.mm
  ${PORTABLE}/audio_pump.cpp ${PORTABLE}/replay_ring.cpp ${PORTABLE}/bench.cpp ${PORTABLE}/soak.cpp ${PORTABLE}/pump_text.cpp)
target_include_directories(intono_ios_shim PUBLIC include PRIVATE ${PORTABLE} ${CMAKE_CURRENT_SOURCE_DIR}/../../dsp/src)
target_compile_options(intono_ios_shim PRIVATE -Wall -Wextra -Wno-unused-parameter $<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)
target_link_libraries(intono_ios_shim PUBLIC intono)
