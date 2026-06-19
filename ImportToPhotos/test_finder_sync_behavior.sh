#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/ImportToPhotos.app/Contents/MacOS/ImportToPhotos"
MARKER_NAME="local.import-to-photos.uploaded"

if [[ ! -x "$BINARY" ]]; then
  echo "Missing binary: $BINARY" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SOURCE_DIR="$TMP_DIR/source"
UPLOAD_DIR="$TMP_DIR/upload"
mkdir -p "$SOURCE_DIR" "$UPLOAD_DIR"

base64 -D > "$SOURCE_DIR/photo.png" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=
PNG

ELIGIBLE_OUTPUT="$("$BINARY" --menu-eligible "$SOURCE_DIR/photo.png")"
grep -q "ELIGIBLE" <<< "$ELIGIBLE_OUTPUT"

SYNC_OUTPUT="$(IMPORT_TO_PHOTOS_DEFAULT_FOLDER="$UPLOAD_DIR" "$BINARY" --sync-copy-test-run "$SOURCE_DIR/photo.png")"
grep -q "COPIED .*photo.png" <<< "$SYNC_OUTPUT"
grep -q "MARKED_SOURCE .*photo.png" <<< "$SYNC_OUTPUT"
grep -q "MARKED_BACKUP .*photo.png" <<< "$SYNC_OUTPUT"

test -f "$UPLOAD_DIR/photo.png"
xattr -p "$MARKER_NAME" "$SOURCE_DIR/photo.png" >/dev/null
xattr -p "$MARKER_NAME" "$UPLOAD_DIR/photo.png" >/dev/null

MENU_CHECK_OUTPUT="$TMP_DIR/menu-check.out"
if "$BINARY" --menu-eligible "$SOURCE_DIR/photo.png" >"$MENU_CHECK_OUTPUT" 2>&1; then
  cat "$MENU_CHECK_OUTPUT" >&2
  echo "Marked source should not be menu eligible" >&2
  exit 1
fi
grep -q "INELIGIBLE" "$MENU_CHECK_OUTPUT"
