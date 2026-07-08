#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCES_DIR="$ROOT_DIR/Sources"
RESOURCES_SOURCE_DIR="$ROOT_DIR/Resources"
TOOLS_DIR="$ROOT_DIR/Tools"
BUILD_DIR="$ROOT_DIR/.build"
OUTPUTS_DIR="$BUILD_DIR/outputs"
APP_DIR="$ROOT_DIR/dist/ImportToPhotos.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLUGINS_DIR="$CONTENTS_DIR/PlugIns"
EXTENSION_DIR="$PLUGINS_DIR/SyncToPhotosFinder.appex"
EXTENSION_CONTENTS_DIR="$EXTENSION_DIR/Contents"
EXTENSION_MACOS_DIR="$EXTENSION_CONTENTS_DIR/MacOS"
CACHE_DIR="$BUILD_DIR/module-cache"
ICON_OUTPUT="$OUTPUTS_DIR/ImportToPhotos.icns"
BUILD_MODE="native"
TARGET_ARCHS=()

while [[ "$#" -gt 0 ]]; do
  arg="$1"
  case "$arg" in
    --universal)
      BUILD_MODE="universal"
      shift
      ;;
    --arch)
      if [[ "$#" -lt 2 ]]; then
        echo "--arch requires arm64 or x86_64" >&2
        exit 64
      fi
      BUILD_MODE="$2"
      shift 2
      ;;
    --arch=*)
      BUILD_MODE="${arg#--arch=}"
      shift
      ;;
    -h|--help)
      echo "usage: $0 [--universal|--arch arm64|--arch x86_64]"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 64
      ;;
  esac
done

case "$BUILD_MODE" in
  native)
    TARGET_ARCHS=("")
    ;;
  universal)
    TARGET_ARCHS=("arm64" "x86_64")
    ;;
  arm64|x86_64)
    TARGET_ARCHS=("$BUILD_MODE")
    ;;
  *)
    echo "Unsupported architecture: $BUILD_MODE" >&2
    exit 64
    ;;
esac

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$EXTENSION_MACOS_DIR" "$CACHE_DIR" "$OUTPUTS_DIR"
cp "$RESOURCES_SOURCE_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$RESOURCES_SOURCE_DIR/FinderSyncExtension/Info.plist" "$EXTENSION_CONTENTS_DIR/Info.plist"
if [[ -f "$RESOURCES_SOURCE_DIR/DefaultImportFolder.txt" ]]; then
  cp "$RESOURCES_SOURCE_DIR/DefaultImportFolder.txt" "$RESOURCES_DIR/DefaultImportFolder.txt"
fi

export CLANG_MODULE_CACHE_PATH="$CACHE_DIR"
export SWIFT_MODULE_CACHE_PATH="$CACHE_DIR"

if [[ ! -f "$ICON_OUTPUT" || "$TOOLS_DIR/make_icon.swift" -nt "$ICON_OUTPUT" ]]; then
  swiftc \
    -framework AppKit \
    -framework CoreGraphics \
    -framework ImageIO \
    -framework UniformTypeIdentifiers \
    "$TOOLS_DIR/make_icon.swift" \
    -o "$BUILD_DIR/make_icon"
  "$BUILD_DIR/make_icon" "$OUTPUTS_DIR"
fi

cp "$ICON_OUTPUT" "$RESOURCES_DIR/ImportToPhotos.icns"

shared_sources=(
  "$SOURCES_DIR/Shared/AppConfig.swift"
  "$SOURCES_DIR/Shared/FileLogWriter.swift"
  "$SOURCES_DIR/Shared/FinderSyncJob.swift"
  "$SOURCES_DIR/Shared/FinderSyncJobQueue.swift"
  "$SOURCES_DIR/Shared/ImageTypePolicy.swift"
  "$SOURCES_DIR/Shared/UploadedMarkerStore.swift"
)

app_sources=(
  "$SOURCES_DIR/App/AppLogger.swift"
  "$SOURCES_DIR/App/CommandLineOptions.swift"
  "$SOURCES_DIR/App/ImageScanner.swift"
  "$SOURCES_DIR/App/NoticeKind.swift"
  "$SOURCES_DIR/App/NoticePresenter.swift"
  "$SOURCES_DIR/App/PhotosImporter.swift"
  "$SOURCES_DIR/App/FinderSyncCopyService.swift"
  "$SOURCES_DIR/App/BackgroundJobAgent.swift"
  "$SOURCES_DIR/App/AppDelegate.swift"
  "$SOURCES_DIR/App/ImportToPhotosMain.swift"
)

extension_sources=(
  "$SOURCES_DIR/FinderSyncExtension/FinderBadgeController.swift"
  "$SOURCES_DIR/FinderSyncExtension/FinderMenuController.swift"
  "$SOURCES_DIR/FinderSyncExtension/FinderSyncExtension.swift"
  "$SOURCES_DIR/FinderSyncExtension/FinderSyncLogger.swift"
)

target_args_for_arch() {
  local arch="$1"
  if [[ -n "$arch" ]]; then
    echo "-target" "$arch-apple-macos12.0"
  fi
}

build_app_binary() {
  local arch="$1"
  local output="$2"
  local target_args=($(target_args_for_arch "$arch"))

  swiftc -O \
    "${target_args[@]}" \
    -framework AppKit \
    -framework Foundation \
    -framework ImageIO \
    -framework Photos \
    -framework UniformTypeIdentifiers \
    "${shared_sources[@]}" \
    "${app_sources[@]}" \
    -o "$output"
}

build_extension_binary() {
  local arch="$1"
  local output="$2"
  local target_args=($(target_args_for_arch "$arch"))

  swiftc -O \
    "${target_args[@]}" \
    -module-name SyncToPhotosFinder \
    -framework AppKit \
    -framework FinderSync \
    -framework Foundation \
    -framework ImageIO \
    -framework UniformTypeIdentifiers \
    -Xlinker -e \
    -Xlinker _NSExtensionMain \
    "${shared_sources[@]}" \
    "${extension_sources[@]}" \
    -o "$output"
}

APP_OUTPUT="$MACOS_DIR/ImportToPhotos"
EXTENSION_OUTPUT="$EXTENSION_MACOS_DIR/SyncToPhotosFinder"
if [[ "${#TARGET_ARCHS[@]}" -eq 1 && -z "${TARGET_ARCHS[1]}" ]]; then
  build_app_binary "" "$APP_OUTPUT"
  build_extension_binary "" "$EXTENSION_OUTPUT"
elif [[ "${#TARGET_ARCHS[@]}" -eq 1 ]]; then
  build_app_binary "${TARGET_ARCHS[1]}" "$APP_OUTPUT"
  build_extension_binary "${TARGET_ARCHS[1]}" "$EXTENSION_OUTPUT"
else
  app_arch_outputs=()
  extension_arch_outputs=()
  for arch in "${TARGET_ARCHS[@]}"; do
    app_arch_output="$OUTPUTS_DIR/ImportToPhotos-$arch"
    extension_arch_output="$OUTPUTS_DIR/SyncToPhotosFinder-$arch"
    build_app_binary "$arch" "$app_arch_output"
    build_extension_binary "$arch" "$extension_arch_output"
    app_arch_outputs+=("$app_arch_output")
    extension_arch_outputs+=("$extension_arch_output")
  done
  lipo -create -output "$APP_OUTPUT" "${app_arch_outputs[@]}"
  lipo -create -output "$EXTENSION_OUTPUT" "${extension_arch_outputs[@]}"
fi

chmod +x "$APP_OUTPUT"
chmod +x "$EXTENSION_OUTPUT"

codesign --force --sign - \
  --entitlements "$RESOURCES_SOURCE_DIR/FinderSyncExtension/SyncToPhotosFinder.entitlements" \
  "$EXTENSION_DIR" >/dev/null
codesign --force --sign - "$APP_DIR" >/dev/null

echo "Built $APP_DIR"
