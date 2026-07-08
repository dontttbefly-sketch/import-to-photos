#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="$ROOT_DIR/dist/ImportToPhotos.app/Contents/MacOS/ImportToPhotos"
MARKER_NAME="local.import-to-photos.uploaded"
MARKER_VALUE='{"version":1,"importedAt":"2026-05-15T00:00:00Z","appIdentifier":"local.import-to-photos"}'

if [[ ! -x "$BINARY" ]]; then
  echo "Missing binary: $BINARY" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

base64 -D > "$TMP_DIR/source.png" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=
PNG

cp "$TMP_DIR/source.png" "$TMP_DIR/unmarked.png"
cp "$TMP_DIR/source.png" "$TMP_DIR/marked.png"
printf "not a real image\n" > "$TMP_DIR/fake.avif"
rm "$TMP_DIR/source.png"
xattr -w "$MARKER_NAME" "$MARKER_VALUE" "$TMP_DIR/marked.png"

OUTPUT="$("$BINARY" --dry-run "$TMP_DIR")"

grep -q "New images: 1" <<< "$OUTPUT"
grep -q "Skipped marked images: 1" <<< "$OUTPUT"
grep -q "NEW .*unmarked.png" <<< "$OUTPUT"
grep -q "SKIPPED .*marked.png" <<< "$OUTPUT"
if grep -q "fake.avif" <<< "$OUTPUT"; then
  echo "Dry-run should not include fake known-extension images that ImageIO cannot open." >&2
  exit 1
fi

cp "$TMP_DIR/unmarked.png" "$TMP_DIR/-dash.png"
DASH_OUTPUT="$("$BINARY" --dry-run -- "$TMP_DIR/-dash.png")"
grep -q "Found 1 supported image(s)." <<< "$DASH_OUTPUT"
grep -q "NEW .*\\-dash.png" <<< "$DASH_OUTPUT"
