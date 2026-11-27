#!/usr/bin/env bash
# Builds IntonoNative.xcframework (ADR 0010): one static library per slice (libintono + pffft + the shim, merged with libtool) and the
# Swift module headers. macOS with Xcode only.  Usage: ios/shim/build_xcframework.sh OUTPUT_DIR
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:?output directory}"
BUILD="${BUILD_DIR:-$HERE/../../build/ios-shim}"
build() {   # name sdk archs
  cmake -S "$HERE" -B "$BUILD/$1" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$2" -DCMAKE_OSX_ARCHITECTURES="$3" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_BUILD_TYPE=Release -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
  cmake --build "$BUILD/$1"
  libtool -static -o "$BUILD/$1/libIntonoNative.a" "$BUILD/$1/libintono_ios_shim.a" \
    "$(find "$BUILD/$1/dsp" -name libintono.a | head -1)" "$(find "$BUILD/$1/dsp" -name libpffft.a | head -1)"
}
build device iphoneos "arm64"
build sim iphonesimulator "arm64;x86_64"
HDR="$BUILD/headers"
rm -rf "$HDR" && mkdir -p "$HDR" && cp "$HERE/include/intono_ios.h" "$HERE/include/module.modulemap" "$HDR/"
rm -rf "$OUT/IntonoNative.xcframework"
mkdir -p "$OUT"
xcodebuild -create-xcframework \
  -library "$BUILD/device/libIntonoNative.a" -headers "$HDR" \
  -library "$BUILD/sim/libIntonoNative.a" -headers "$HDR" \
  -output "$OUT/IntonoNative.xcframework"
for lib in "$BUILD/device/libIntonoNative.a" "$BUILD/sim/libIntonoNative.a"; do
  lipo -info "$lib"
  for sym in intono_create intono_process intono_read_frames intono_bench_run intono_ios_start intono_ios_link_c_api; do
    nm -gU "$lib" 2>/dev/null | grep -q " T _$sym$" || { echo "$lib: _$sym missing"; exit 1; }
  done
done
echo "built $OUT/IntonoNative.xcframework"
