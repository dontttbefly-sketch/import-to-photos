#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/ImportToPhotos.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLUGINS_DIR="$CONTENTS_DIR/PlugIns"
EXTENSION_SOURCE_DIR="$SCRIPT_DIR/FinderSyncExtension"
EXTENSION_DIR="$PLUGINS_DIR/SyncToPhotosFinder.appex"
EXTENSION_CONTENTS_DIR="$EXTENSION_DIR/Contents"
EXTENSION_MACOS_DIR="$EXTENSION_CONTENTS_DIR/MacOS"
CACHE_DIR="$SCRIPT_DIR/.build/module-cache"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$EXTENSION_MACOS_DIR" "$CACHE_DIR"
cp "$SCRIPT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$EXTENSION_SOURCE_DIR/Info.plist" "$EXTENSION_CONTENTS_DIR/Info.plist"
if [[ -f "$SCRIPT_DIR/DefaultImportFolder.txt" ]]; then
  cp "$SCRIPT_DIR/DefaultImportFolder.txt" "$RESOURCES_DIR/DefaultImportFolder.txt"
fi

export CLANG_MODULE_CACHE_PATH="$CACHE_DIR"
export SWIFT_MODULE_CACHE_PATH="$CACHE_DIR"

if [[ ! -f "$SCRIPT_DIR/ImportToPhotos.icns" || "$SCRIPT_DIR/make_icon.swift" -nt "$SCRIPT_DIR/ImportToPhotos.icns" ]]; then
  swiftc \
    -framework AppKit \
    -framework CoreGraphics \
    -framework ImageIO \
    -framework UniformTypeIdentifiers \
    "$SCRIPT_DIR/make_icon.swift" \
    -o "$SCRIPT_DIR/.build/make_icon"
  "$SCRIPT_DIR/.build/make_icon" "$SCRIPT_DIR"
fi

cp "$SCRIPT_DIR/ImportToPhotos.icns" "$RESOURCES_DIR/ImportToPhotos.icns"

swiftc -O \
  -framework AppKit \
  -framework Foundation \
  -framework Photos \
  -framework UniformTypeIdentifiers \
  "$SCRIPT_DIR/ImportToPhotosShared.swift" \
  "$SCRIPT_DIR/ImportToPhotos.swift" \
  -o "$MACOS_DIR/ImportToPhotos"

swiftc -O \
  -module-name SyncToPhotosFinder \
  -framework AppKit \
  -framework FinderSync \
  -framework Foundation \
  -framework UniformTypeIdentifiers \
  -Xlinker -e \
  -Xlinker _NSExtensionMain \
  "$SCRIPT_DIR/ImportToPhotosShared.swift" \
  "$EXTENSION_SOURCE_DIR/FinderSyncExtension.swift" \
  -o "$EXTENSION_MACOS_DIR/SyncToPhotosFinder"

chmod +x "$MACOS_DIR/ImportToPhotos"
chmod +x "$EXTENSION_MACOS_DIR/SyncToPhotosFinder"

codesign --force --sign - \
  --entitlements "$EXTENSION_SOURCE_DIR/SyncToPhotosFinder.entitlements" \
  "$EXTENSION_DIR" >/dev/null
codesign --force --sign - "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
