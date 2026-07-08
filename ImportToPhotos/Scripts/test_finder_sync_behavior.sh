#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BINARY="$ROOT_DIR/dist/ImportToPhotos.app/Contents/MacOS/ImportToPhotos"
MARKER_NAME="local.import-to-photos.uploaded"

if [[ ! -x "$BINARY" ]]; then
  echo "Missing binary: $BINARY" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
export IMPORT_TO_PHOTOS_APP_LOG_PATH="$TMP_DIR/app.log"

SOURCE_DIR="$TMP_DIR/source"
UPLOAD_DIR="$TMP_DIR/upload"
mkdir -p "$SOURCE_DIR" "$UPLOAD_DIR"

base64 -D > "$SOURCE_DIR/photo.png" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=
PNG
printf "not an image\n" > "$SOURCE_DIR/note.txt"
printf "menu eligibility only\n" > "$SOURCE_DIR/sample.avif"
printf "raw placeholder\n" > "$SOURCE_DIR/sample.cr3"
cp "$SOURCE_DIR/photo.png" "$SOURCE_DIR/second.png"
mkdir -p "$SOURCE_DIR/.git"
cp "$SOURCE_DIR/photo.png" "$SOURCE_DIR/.git/excluded.png"

DENIED_LOCKED_OUTPUT="$TMP_DIR/denied-locked.out"
if IMPORT_TO_PHOTOS_DEFAULT_FOLDER="$UPLOAD_DIR" "$BINARY" --sync-copy-denied-test-run "$SOURCE_DIR/photo.png" >"$DENIED_LOCKED_OUTPUT" 2>&1; then
  cat "$DENIED_LOCKED_OUTPUT" >&2
  echo "Hidden test hooks must require IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1." >&2
  exit 1
fi
grep -q "TEST_HOOKS_DISABLED" "$DENIED_LOCKED_OUTPUT"

DENIED_OUTPUT="$(IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1 IMPORT_TO_PHOTOS_DEFAULT_FOLDER="$UPLOAD_DIR" "$BINARY" --sync-copy-denied-test-run "$SOURCE_DIR/photo.png")"
grep -q "需要授权" <<< "$DENIED_OUTPUT"
grep -q "IMPORTED 0" <<< "$DENIED_OUTPUT"
if [[ -e "$UPLOAD_DIR/photo.png" ]]; then
  echo "Denied Photos access must not copy into upload folder." >&2
  exit 1
fi

ELIGIBLE_OUTPUT="$("$BINARY" --menu-eligible "$SOURCE_DIR/photo.png")"
grep -q "ELIGIBLE" <<< "$ELIGIBLE_OUTPUT"

AVIF_ELIGIBLE_OUTPUT="$("$BINARY" --menu-eligible "$SOURCE_DIR/sample.avif")"
grep -q "ELIGIBLE" <<< "$AVIF_ELIGIBLE_OUTPUT"

AVIF_COPY_OUTPUT="$(IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1 IMPORT_TO_PHOTOS_DEFAULT_FOLDER="$UPLOAD_DIR" "$BINARY" --sync-copy-test-run "$SOURCE_DIR/sample.avif" || true)"
grep -q "FAILED .*sample.avif" <<< "$AVIF_COPY_OUTPUT"

RAW_COPY_OUTPUT="$(IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1 IMPORT_TO_PHOTOS_DEFAULT_FOLDER="$UPLOAD_DIR" "$BINARY" --sync-copy-test-run "$SOURCE_DIR/sample.cr3")"
grep -q "COPIED .*sample.cr3" <<< "$RAW_COPY_OUTPUT"
grep -q "MARKED_SOURCE .*sample.cr3" <<< "$RAW_COPY_OUTPUT"

SUPPORT_OUTPUT="$("$BINARY" --dry-run --image-support-check "$SOURCE_DIR/photo.png" "$SOURCE_DIR/sample.avif" "$SOURCE_DIR/sample.cr3" || true)"
grep -q "SUPPORTED .*photo.png" <<< "$SUPPORT_OUTPUT"
grep -q "UNSUPPORTED .*sample.avif" <<< "$SUPPORT_OUTPUT"
grep -q "POSSIBLE_RAW .*sample.cr3" <<< "$SUPPORT_OUTPUT"

NON_IMAGE_OUTPUT="$TMP_DIR/non-image.out"
if "$BINARY" --menu-eligible "$SOURCE_DIR/note.txt" >"$NON_IMAGE_OUTPUT" 2>&1; then
  cat "$NON_IMAGE_OUTPUT" >&2
  echo "Non-image text file should not be menu eligible" >&2
  exit 1
fi
grep -q "INELIGIBLE" "$NON_IMAGE_OUTPUT"

EXCLUDED_OUTPUT="$TMP_DIR/excluded.out"
if "$BINARY" --menu-eligible "$SOURCE_DIR/.git/excluded.png" >"$EXCLUDED_OUTPUT" 2>&1; then
  cat "$EXCLUDED_OUTPUT" >&2
  echo "Images inside excluded directories should not be menu eligible" >&2
  exit 1
fi
grep -q "INELIGIBLE" "$EXCLUDED_OUTPUT"

MIXED_OUTPUT="$TMP_DIR/mixed.out"
if "$BINARY" --menu-eligible "$SOURCE_DIR/photo.png" "$SOURCE_DIR/note.txt" >"$MIXED_OUTPUT" 2>&1; then
  cat "$MIXED_OUTPUT" >&2
  echo "Mixed image and non-image selections should not be menu eligible" >&2
  exit 1
fi
grep -q "INELIGIBLE" "$MIXED_OUTPUT"

SYNC_OUTPUT="$(IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1 IMPORT_TO_PHOTOS_DEFAULT_FOLDER="$UPLOAD_DIR" "$BINARY" --sync-copy-test-run "$SOURCE_DIR/photo.png")"
grep -q "COPIED .*photo.png" <<< "$SYNC_OUTPUT"
grep -q "MARKED_SOURCE .*photo.png" <<< "$SYNC_OUTPUT"
grep -q "MARKED_BACKUP .*photo.png" <<< "$SYNC_OUTPUT"

cp "$SOURCE_DIR/photo.png" "$SOURCE_DIR/retry.png"
xattr -d "$MARKER_NAME" "$SOURCE_DIR/retry.png" 2>/dev/null || true
FIRST_STAGE_OUTPUT="$(IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1 IMPORT_TO_PHOTOS_DEFAULT_FOLDER="$UPLOAD_DIR" "$BINARY" --sync-copy-test-run "$SOURCE_DIR/retry.png")"
grep -q "COPIED .*retry.png" <<< "$FIRST_STAGE_OUTPUT"
xattr -d "$MARKER_NAME" "$SOURCE_DIR/retry.png" 2>/dev/null || true
xattr -d "$MARKER_NAME" "$UPLOAD_DIR/retry.png" 2>/dev/null || true
SECOND_STAGE_OUTPUT="$(IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1 IMPORT_TO_PHOTOS_DEFAULT_FOLDER="$UPLOAD_DIR" "$BINARY" --sync-copy-test-run "$SOURCE_DIR/retry.png")"
if [[ -e "$UPLOAD_DIR/retry 2.png" ]]; then
  echo "Retry staging should reuse an identical existing backup instead of creating retry 2.png." >&2
  echo "$SECOND_STAGE_OUTPUT" >&2
  exit 1
fi

MIXED_SYNC_OUTPUT="$(IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1 IMPORT_TO_PHOTOS_DEFAULT_FOLDER="$UPLOAD_DIR" "$BINARY" --sync-copy-test-run "$SOURCE_DIR/second.png" "$SOURCE_DIR/note.txt" || true)"
grep -q "COPIED .*second.png" <<< "$MIXED_SYNC_OUTPUT"
grep -q "FAILED .*note.txt" <<< "$MIXED_SYNC_OUTPUT"

cp "$SOURCE_DIR/photo.png" "$SOURCE_DIR/partial-ok.png"
cp "$SOURCE_DIR/photo.png" "$SOURCE_DIR/partial-fail.png"
xattr -d "$MARKER_NAME" "$SOURCE_DIR/partial-ok.png" 2>/dev/null || true
xattr -d "$MARKER_NAME" "$SOURCE_DIR/partial-fail.png" 2>/dev/null || true
PARTIAL_OUTPUT="$(IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1 IMPORT_TO_PHOTOS_DEFAULT_FOLDER="$UPLOAD_DIR" "$BINARY" --sync-copy-partial-test-run "$SOURCE_DIR/partial-ok.png" "$SOURCE_DIR/partial-fail.png")"
grep -q "NOTICE 部分失败" <<< "$PARTIAL_OUTPUT"
grep -q "IMPORTED 1" <<< "$PARTIAL_OUTPUT"
grep -q "FAILURES 1" <<< "$PARTIAL_OUTPUT"
grep -q "RESOLUTION retryLater" <<< "$PARTIAL_OUTPUT"
grep -q "RETRY_PATH .*partial-fail.png" <<< "$PARTIAL_OUTPUT"
grep -q "RETRY_STAGED_PATH .*partial-fail.png" <<< "$PARTIAL_OUTPUT"
if grep -q "RETRY_PATH .*partial-ok.png" <<< "$PARTIAL_OUTPUT"; then
  echo "Partial retry should only include the failed source." >&2
  echo "$PARTIAL_OUTPUT" >&2
  exit 1
fi

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

JOB_DIR="$TMP_DIR/jobs"
mkdir -p "$JOB_DIR"
cat > "$JOB_DIR/recover-me.processing" <<EOF
{"id":"recover-me","createdAt":"2026-07-08T00:00:00Z","paths":["$SOURCE_DIR/photo.png"]}
EOF
QUEUE_OUTPUT="$(IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1 IMPORT_TO_PHOTOS_JOB_DIR="$JOB_DIR" "$BINARY" --queue-recovery-test-run)"
grep -q "CLAIMED recover-me" <<< "$QUEUE_OUTPUT"
if [[ -e "$JOB_DIR/recover-me.processing" || -e "$JOB_DIR/recover-me.json" ]]; then
  echo "Recovered queue job should be claimed and completed." >&2
  exit 1
fi

RETRY_DIR="$TMP_DIR/retry-jobs"
mkdir -p "$RETRY_DIR"
cat > "$RETRY_DIR/retry-me.json" <<EOF
{"id":"retry-me","createdAt":"2026-07-08T00:00:00Z","paths":["$SOURCE_DIR/photo.png"]}
EOF
RETRY_OUTPUT="$(IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1 IMPORT_TO_PHOTOS_JOB_DIR="$RETRY_DIR" "$BINARY" --queue-retry-test-run)"
grep -q "RETRY_PENDING retry-me attempt=1" <<< "$RETRY_OUTPUT"
test -f "$RETRY_DIR/retry-me.json"
grep -q '"attemptCount"[[:space:]]*:[[:space:]]*1' "$RETRY_DIR/retry-me.json"
grep -q '"nextAttemptAt"' "$RETRY_DIR/retry-me.json"
if [[ -e "$RETRY_DIR/retry-me.failed" ]]; then
  echo "Retryable queue failures should not be moved to .failed." >&2
  exit 1
fi
if [[ -e "$RETRY_DIR/retry-me.processing" ]]; then
  echo "Retryable queue failures should be written back as scheduled .json jobs, not left in .processing." >&2
  exit 1
fi

WRITE_FAIL_DIR="$TMP_DIR/write-fail-jobs"
mkdir -p "$WRITE_FAIL_DIR"
cat > "$WRITE_FAIL_DIR/write-fails.json" <<EOF
{"id":"write-fails","createdAt":"2026-07-08T00:00:00Z","paths":["$SOURCE_DIR/photo.png"]}
EOF
WRITE_FAIL_OUTPUT="$(IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1 IMPORT_TO_PHOTOS_FORCE_RETRY_WRITE_FAILURE=1 IMPORT_TO_PHOTOS_JOB_DIR="$WRITE_FAIL_DIR" "$BINARY" --queue-retry-test-run || true)"
chmod u+w "$WRITE_FAIL_DIR" 2>/dev/null || true
grep -q "QUEUE_ERROR" <<< "$WRITE_FAIL_OUTPUT"
test -f "$WRITE_FAIL_DIR/write-fails.processing"
if [[ -e "$WRITE_FAIL_DIR/write-fails.json" || -e "$WRITE_FAIL_DIR/write-fails.failed" ]]; then
  echo "A failed retry write must leave the claimed processing job intact without claiming success." >&2
  echo "$WRITE_FAIL_OUTPUT" >&2
  exit 1
fi

EXHAUSTED_DIR="$TMP_DIR/exhausted-jobs"
mkdir -p "$EXHAUSTED_DIR"
cat > "$EXHAUSTED_DIR/exhausted-me.json" <<EOF
{"id":"exhausted-me","createdAt":"2026-07-08T00:00:00Z","paths":["$SOURCE_DIR/photo.png"],"attemptCount":2,"maxAttempts":3}
EOF
EXHAUSTED_OUTPUT="$(IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS=1 IMPORT_TO_PHOTOS_JOB_DIR="$EXHAUSTED_DIR" "$BINARY" --queue-retry-test-run)"
grep -q "RETRY_EXHAUSTED exhausted-me attempt=3" <<< "$EXHAUSTED_OUTPUT"
test -f "$EXHAUSTED_DIR/exhausted-me.failed"
grep -q '"lastError"' "$EXHAUSTED_DIR/exhausted-me.failed"
