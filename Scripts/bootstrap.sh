#!/usr/bin/env bash
# Sets up a clean clone: submodules, local vcpkg, emulator core build, Xcode project.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

for tool in cmake ninja pkg-config xcodegen; do
  command -v "$tool" >/dev/null || { echo "Missing $tool — run: brew install cmake ninja pkg-config autoconf automake libtool xcodegen"; exit 1; }
done

git submodule update --init --recursive

export VCPKG_ROOT="$ROOT/.tools/vcpkg"
if [[ ! -x "$VCPKG_ROOT/vcpkg" ]]; then
  git clone --quiet https://github.com/microsoft/vcpkg "$VCPKG_ROOT"
  "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics
fi

"$ROOT/Scripts/build-core.sh"
xcodegen generate --quiet
echo "Done. Open DOSBoxer.xcodeproj"
