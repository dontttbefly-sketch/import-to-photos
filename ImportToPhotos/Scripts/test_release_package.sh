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

grep -q "pluginkit -m" "$PACKAGE_DIR/Doctor.command"
grep -q "WARNING" "$PACKAGE_DIR/Doctor.command"
grep -q "Finder Sync extension process" "$PACKAGE_DIR/Doctor.command"

ZIP_LIST="$(zipinfo -1 "$ZIP_PATH")"
grep -q "ImportToPhotos-v9.9.9-.*/Install.command" <<< "$ZIP_LIST"
grep -q "ImportToPhotos-v9.9.9-.*/Payload/Applications/ImportToPhotos.app/Contents/MacOS/ImportToPhotos" <<< "$ZIP_LIST"

grep -q "package_release.sh" "$ROOT_DIR/../README.md"
grep -q "GitHub Release" "$ROOT_DIR/../README.md"
grep -q "不要点.*Code.*Download ZIP" "$ROOT_DIR/../README.md"
