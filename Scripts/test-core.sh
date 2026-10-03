#!/usr/bin/env bash
# Builds and runs the headless core smoke test. Images land in build/test-output.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/build/core-Release/dosboxer"
OUT="$ROOT/build/test-output"
mkdir -p "$OUT"
c++ -std=c++20 -arch arm64 -mmacosx-version-min=26.0 -I"$ROOT/Core/include" \
  "$ROOT/Core/tests/headless_test.cpp" -L"$LIB" -lDOSBoxerCore -Wl,-rpath,"$LIB" \
  -o "$OUT/headless_test"
# dosbox-staging finds its resources relative to the working directory
cd "$ROOT/Vendor/dosbox-staging"
"$OUT/headless_test" "$OUT" "$@"
