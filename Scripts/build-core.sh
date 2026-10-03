#!/usr/bin/env bash
# Builds the emulator core (dosbox-staging + our host shim) as
# build/core-<Config>/dosboxer/libDOSBoxerCore.dylib for arm64 / macOS 26.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export VCPKG_ROOT="${VCPKG_ROOT:-$ROOT/.tools/vcpkg}"
CONFIG="${CONFIG:-Release}"
BUILD="$ROOT/build/core-$CONFIG"

"$ROOT/Scripts/apply-patches.sh"

cmake -S "$ROOT/Vendor/dosbox-staging" -B "$BUILD" -G Ninja \
  -DIS_PRESET_USED=TRUE \
  -DCMAKE_BUILD_TYPE="$CONFIG" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
  -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
  -DVCPKG_TARGET_TRIPLET=arm64-osx \
  -DVCPKG_INSTALLED_DIR="$ROOT/build/vcpkg_installed" \
  -DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON \
  -DOPT_TESTS=OFF \
  -DCMAKE_IGNORE_PREFIX_PATH="/opt/X11;/usr/X11R6" \
  -DOPENGL_gl_LIBRARY="$(xcrun --show-sdk-path)/System/Library/Frameworks/OpenGL.framework" \
  -DDOSBOXER_HOST_DIR="$ROOT/Core"
cmake --build "$BUILD" --target DOSBoxerCore
