#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/build.sh" >/dev/null

OUTPUT="$("$SCRIPT_DIR/package_release.sh" --skip-build --version 9.9.9)"
PACKAGE_DIR="$(grep '^PACKAGE_DIR=' <<< "$OUTPUT" | cut -d= -f2-)"
PKG_PATH="$(grep '^PKG_PATH=' <<< "$OUTPUT" | cut -d= -f2-)"
DMG_PATH="$(grep '^DMG_PATH=' <<< "$OUTPUT" | cut -d= -f2-)"

test -n "$PACKAGE_DIR"
test -n "$PKG_PATH"
test -n "$DMG_PATH"
test -d "$PACKAGE_DIR"
test -f "$PKG_PATH"
test -f "$DMG_PATH"

test -d "$PACKAGE_DIR/pkg-root/Applications/ImportToPhotos.app"
test -d "$PACKAGE_DIR/pkg-scripts/Resources/ServiceWorkflow/同步进相册.workflow"
test -f "$PACKAGE_DIR/pkg-scripts/Resources/LaunchAgent/local.import-to-photos.agent.plist"
test -f "$PACKAGE_DIR/pkg-scripts/postinstall"
test -f "$PACKAGE_DIR/package-info.txt"
test ! -f "$PACKAGE_DIR/pkg-root/Applications/ImportToPhotos.app/Contents/Resources/DefaultImportFolder.txt"

grep -q '^PACKAGE_NAME=ImportToPhotos-v9.9.9-' "$PACKAGE_DIR/package-info.txt"
grep -q '^VERSION=9.9.9$' "$PACKAGE_DIR/package-info.txt"
grep -q '^CPU_ARCH=' "$PACKAGE_DIR/package-info.txt"
grep -q '^APP_ARCHS=' "$PACKAGE_DIR/package-info.txt"
grep -q '^APP_BINARY_TYPE=' "$PACKAGE_DIR/package-info.txt"
grep -q '^DISTRIBUTION=github-release$' "$PACKAGE_DIR/package-info.txt"
grep -q '^FORMAT=dmg-pkg$' "$PACKAGE_DIR/package-info.txt"
grep -q '^SIGNING=adhoc$' "$PACKAGE_DIR/package-info.txt"
grep -q '^NOTARIZED=no$' "$PACKAGE_DIR/package-info.txt"

test ! -f "$PACKAGE_DIR/Install.command"
test ! -f "$PACKAGE_DIR/Doctor.command"
test ! -f "$PACKAGE_DIR/Uninstall.command"

test -f "$PACKAGE_DIR/dmg-root/README-先读我.md"
grep -q "Install ImportToPhotos.pkg" "$PACKAGE_DIR/dmg-root/README-先读我.md"
grep -q "Photos 权限" "$PACKAGE_DIR/dmg-root/README-先读我.md"
grep -q "★ 同步进相册" "$PACKAGE_DIR/dmg-root/README-先读我.md"
grep -q "GitHub Release" "$PACKAGE_DIR/dmg-root/README-先读我.md"

PACKAGED_BINARY="$PACKAGE_DIR/pkg-root/Applications/ImportToPhotos.app/Contents/MacOS/ImportToPhotos"
TEST_HOME="$PACKAGE_DIR/test-home"
TEST_SOURCE_DIR="$PACKAGE_DIR/test-source"
mkdir -p "$TEST_HOME" "$TEST_SOURCE_DIR"
base64 -D > "$TEST_SOURCE_DIR/photo.png" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=
PNG
DEFAULT_COPY_OUTPUT="$(IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1 IMPORT_TO_PHOTOS_HOME_DIR="$TEST_HOME" "$PACKAGED_BINARY" --sync-copy-test-run "$TEST_SOURCE_DIR/photo.png")"
grep -q "USING_SOURCE $TEST_SOURCE_DIR/photo.png" <<< "$DEFAULT_COPY_OUTPUT"
grep -q "MARKED_SOURCE $TEST_SOURCE_DIR/photo.png" <<< "$DEFAULT_COPY_OUTPUT"
if grep -q "MARKED_BACKUP" <<< "$DEFAULT_COPY_OUTPUT"; then
  echo "Finder right-click release behavior must not mark a copied backup by default." >&2
  exit 1
fi
if [[ -e "$TEST_HOME/Pictures/ImportToPhotos/photo.png" ]]; then
  echo "Finder right-click release behavior must not create a retained copy by default." >&2
  exit 1
fi

grep -q "stat -f %Su /dev/console" "$PACKAGE_DIR/pkg-scripts/postinstall"
grep -q "Library/Services" "$PACKAGE_DIR/pkg-scripts/postinstall"
grep -q "Library/LaunchAgents" "$PACKAGE_DIR/pkg-scripts/postinstall"
grep -q "pluginkit -e use" "$PACKAGE_DIR/pkg-scripts/postinstall"
grep -q "launchctl bootstrap" "$PACKAGE_DIR/pkg-scripts/postinstall"

PAYLOAD_FILES="$(pkgutil --payload-files "$PKG_PATH")"
grep -q "Applications/ImportToPhotos.app/Contents/MacOS/ImportToPhotos" <<< "$PAYLOAD_FILES"
if grep -q "DefaultImportFolder.txt" <<< "$PAYLOAD_FILES"; then
  echo "Installer pkg must not include local DefaultImportFolder.txt" >&2
  exit 1
fi

DMG_INFO="$(hdiutil imageinfo "$DMG_PATH")"
grep -q "Format: UDZO" <<< "$DMG_INFO"

MOUNT_DIR="$PACKAGE_DIR/dmg-mount"
mkdir -p "$MOUNT_DIR"
hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" >/dev/null
detach_dmg() {
  hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
}
trap detach_dmg EXIT
test -f "$MOUNT_DIR/Install ImportToPhotos.pkg"
test -f "$MOUNT_DIR/README-先读我.md"
if [[ -e "$MOUNT_DIR/Install.command" ]]; then
  echo "Release DMG must not expose Install.command as the primary installer." >&2
  exit 1
fi

grep -q "package_release.sh --universal" "$ROOT_DIR/../README.md"
grep -q "GitHub Release" "$ROOT_DIR/../README.md"
grep -q "下载.*dmg" "$ROOT_DIR/../README.md"
grep -q "Install ImportToPhotos.pkg" "$ROOT_DIR/../README.md"
grep -q "不要点.*Code.*Download ZIP" "$ROOT_DIR/../README.md"
