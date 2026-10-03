#!/usr/bin/env bash
# Applies DOS Boxer's patches to the dosbox-staging submodule (idempotent).
# To update the patch after editing the submodule:
#   git -C Vendor/dosbox-staging add -N . && git -C Vendor/dosbox-staging diff > Core/patches/dosbox-staging.patch
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SUB="$ROOT/Vendor/dosbox-staging"
PATCH="$ROOT/Core/patches/dosbox-staging.patch"

if git -C "$SUB" apply --reverse --check "$PATCH" 2>/dev/null; then
  exit 0  # already applied
fi
git -C "$SUB" apply "$PATCH"
echo "Applied $(basename "$PATCH")"
