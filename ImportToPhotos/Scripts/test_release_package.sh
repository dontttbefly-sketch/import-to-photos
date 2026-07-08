#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

"$SCRIPT_DIR/build.sh" >/dev/null

OUTPUT="$("$SCRIPT_DIR/package_release.sh" --skip-build --version 9.9.9)"
PACKAGE_DIR="$(grep '^PACKAGE_DIR=' <<< "$OUTPUT" | cut -d= -f2-)"
ZIP_PATH="$(grep '^ZIP_PATH=' <<< "$OUTPUT" | cut -d= -f2-)"

test -n "$PACKAGE_DIR"
test -n "$ZIP_PATH"
test -d "$PACKAGE_DIR"
test -f "$ZIP_PATH"

test -d "$PACKAGE_DIR/Payload/Applications/ImportToPhotos.app"
test -d "$PACKAGE_DIR/Payload/Resources/ServiceWorkflow/同步进相册.workflow"
test -f "$PACKAGE_DIR/Payload/Resources/LaunchAgent/local.import-to-photos.agent.plist"
test -f "$PACKAGE_DIR/package-info.txt"
test ! -f "$PACKAGE_DIR/Payload/Applications/ImportToPhotos.app/Contents/Resources/DefaultImportFolder.txt"

grep -q '^PACKAGE_NAME=ImportToPhotos-v9.9.9-' "$PACKAGE_DIR/package-info.txt"
grep -q '^VERSION=9.9.9$' "$PACKAGE_DIR/package-info.txt"
grep -q '^CPU_ARCH=' "$PACKAGE_DIR/package-info.txt"
grep -q '^APP_ARCHS=' "$PACKAGE_DIR/package-info.txt"
grep -q '^APP_BINARY_TYPE=' "$PACKAGE_DIR/package-info.txt"
grep -q '^DISTRIBUTION=github-release$' "$PACKAGE_DIR/package-info.txt"
grep -q '^SIGNING=adhoc$' "$PACKAGE_DIR/package-info.txt"
grep -q '^NOTARIZED=no$' "$PACKAGE_DIR/package-info.txt"

for command_file in Install.command Doctor.command Uninstall.command; do
  test -f "$PACKAGE_DIR/$command_file"
  test -x "$PACKAGE_DIR/$command_file"
done

test -f "$PACKAGE_DIR/README-先双击我.md"
grep -q "右键.*Install.command" "$PACKAGE_DIR/README-先双击我.md"
grep -q "Photos 权限" "$PACKAGE_DIR/README-先双击我.md"
grep -q "★ 同步进相册" "$PACKAGE_DIR/README-先双击我.md"
grep -q "GitHub Release" "$PACKAGE_DIR/README-先双击我.md"

PACKAGED_BINARY="$PACKAGE_DIR/Payload/Applications/ImportToPhotos.app/Contents/MacOS/ImportToPhotos"
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

grep -q "pluginkit -m" "$PACKAGE_DIR/Doctor.command"
grep -q "WARNING" "$PACKAGE_DIR/Doctor.command"
grep -q "Finder Sync extension process" "$PACKAGE_DIR/Doctor.command"

ZIP_LIST="$(zipinfo -1 "$ZIP_PATH")"
grep -q "ImportToPhotos-v9.9.9-.*/Install.command" <<< "$ZIP_LIST"
grep -q "ImportToPhotos-v9.9.9-.*/Payload/Applications/ImportToPhotos.app/Contents/MacOS/ImportToPhotos" <<< "$ZIP_LIST"
if grep -q "DefaultImportFolder.txt" <<< "$ZIP_LIST"; then
  echo "Release zip must not include local DefaultImportFolder.txt" >&2
  exit 1
fi

grep -q "package_release.sh" "$ROOT_DIR/../README.md"
grep -q "GitHub Release" "$ROOT_DIR/../README.md"
grep -q "不要点.*Code.*Download ZIP" "$ROOT_DIR/../README.md"
