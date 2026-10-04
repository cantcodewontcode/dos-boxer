#!/usr/bin/env bash
# Xcode build phase (DOS Boxer and DOS Boxer Player): puts the emulator core
# library in Frameworks and dosbox-staging's resources in Resources.
set -euo pipefail
FRAMEWORKS="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH"
RESOURCES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
mkdir -p "$FRAMEWORKS" "$RESOURCES"
cp -f "$CORE_BUILD_DIR/libDOSBoxerCore.dylib" "$FRAMEWORKS/"
codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$FRAMEWORKS/libDOSBoxerCore.dylib"
# The engine (in Contents/MacOS) finds dosbox-staging's fonts, keyboard
# layouts and shaders in Contents/Resources
rsync -a --delete-excluded --exclude meson.build --exclude webserver \
  "$SRCROOT/Vendor/dosbox-staging/resources/" "$RESOURCES/dosbox/"
for item in "$RESOURCES/dosbox/"*; do
  ln -sfh "dosbox/$(basename "$item")" "$RESOURCES/$(basename "$item")"
done
