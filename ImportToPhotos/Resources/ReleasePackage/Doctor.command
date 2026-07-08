#!/bin/zsh
set -uo pipefail

APP_DIR="/Applications/ImportToPhotos.app"
APP_BINARY="$APP_DIR/Contents/MacOS/ImportToPhotos"
EXTENSION_DIR="$APP_DIR/Contents/PlugIns/SyncToPhotosFinder.appex"
EXTENSION_ID="local.import-to-photos.finder-sync"
SERVICE_INSTALL_DIR="$HOME/Library/Services/★ 同步进相册.workflow"
LAUNCH_AGENT_INSTALL="$HOME/Library/LaunchAgents/local.import-to-photos.agent.plist"
LAUNCH_AGENT_LABEL="local.import-to-photos.agent"
GUI_DOMAIN="gui/$(id -u)"
APP_LOG="$HOME/Library/Application Support/ImportToPhotos/app.log"
APP_LOG_FALLBACK="/tmp/local.import-to-photos/app.log"
FINDER_LOG="$HOME/Library/Application Support/ImportToPhotos/finder-sync.log"
SHARED_SUPPORT_DIR="$HOME/Library/Containers/local.import-to-photos.finder-sync/Data/Library/Application Support/ImportToPhotos"
HEARTBEAT_FILE="$SHARED_SUPPORT_DIR/finder-sync-heartbeat.log"
JOB_DIR="$SHARED_SUPPORT_DIR/jobs"
NO_PAUSE=0
FAILURES=0
WARNINGS=0

for arg in "$@"; do
  case "$arg" in
    --no-pause)
      NO_PAUSE=1
      ;;
    -h|--help)
      echo "usage: $0 [--no-pause]"
      exit 0
      ;;
  esac
done

pause_if_needed() {
  if [[ "$NO_PAUSE" != "1" ]]; then
    echo
    read -r "?按回车键关闭这个窗口..."
  fi
}

pass() {
  echo "PASS: $1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  echo "WARNING: $1"
}

fail() {
  FAILURES=$((FAILURES + 1))
  echo "FAIL: $1"
}

check_path() {
  local label="$1"
  local path="$2"
  if [[ -e "$path" ]]; then
    pass "$label: $path"
  else
    fail "$label missing: $path"
  fi
}

echo "ImportToPhotos Doctor"
echo

check_path "Installed app" "$APP_DIR"
check_path "App binary" "$APP_BINARY"
check_path "Finder Sync extension" "$EXTENSION_DIR"
check_path "Service workflow" "$SERVICE_INSTALL_DIR"
check_path "LaunchAgent plist" "$LAUNCH_AGENT_INSTALL"

if [[ -x "$APP_BINARY" ]]; then
  APP_ARCHS="$(lipo -archs "$APP_BINARY" 2>/dev/null || true)"
  MACHINE_ARCH="$(uname -m)"
  if [[ -n "$APP_ARCHS" && " $APP_ARCHS " == *" $MACHINE_ARCH "* ]]; then
    pass "CPU architecture matches: $APP_ARCHS"
  else
    fail "CPU architecture mismatch. app=$APP_ARCHS machine=$MACHINE_ARCH"
  fi

  if "$APP_BINARY" --help >/dev/null 2>&1; then
    pass "App can launch with --help"
  else
    fail "App cannot launch with --help"
  fi

  if codesign --verify --deep --strict "$APP_DIR" >/dev/null 2>&1; then
    pass "Adhoc code signature verifies"
  else
    warn "Code signature verification failed"
  fi
fi

if launchctl print "$GUI_DOMAIN/$LAUNCH_AGENT_LABEL" >/dev/null 2>&1; then
  pass "LaunchAgent is registered"
else
  warn "LaunchAgent is not registered yet"
fi

if pgrep -fl "/Applications/ImportToPhotos.app/Contents/MacOS/ImportToPhotos.*--background-agent" >/dev/null 2>&1; then
  pass "Background agent process is running"
else
  warn "Background agent process is not visible"
fi

if pgrep -fl "SyncToPhotosFinder" >/dev/null 2>&1; then
  pass "Finder Sync extension process is running"
else
  warn "Finder Sync extension process is not visible. Right-click a Finder item or restart Finder."
fi

if pluginkit -m -i "$EXTENSION_ID" >/tmp/import-to-photos-pluginkit.out 2>&1; then
  pass "pluginkit -m can query the extension"
else
  warn "pluginkit -m could not query the extension. This macOS diagnostic can be flaky; process and logs matter more."
  cat /tmp/import-to-photos-pluginkit.out 2>/dev/null || true
fi

if [[ -f "$HEARTBEAT_FILE" ]]; then
  HEARTBEAT_MTIME="$(stat -f %m "$HEARTBEAT_FILE" 2>/dev/null || echo 0)"
  NOW_SECONDS="$(date +%s)"
  HEARTBEAT_AGE=$((NOW_SECONDS - HEARTBEAT_MTIME))
  if [[ "$HEARTBEAT_AGE" -le 900 ]]; then
    pass "Finder Sync heartbeat is recent: ${HEARTBEAT_AGE}s ago"
  else
    warn "Finder Sync heartbeat is old: ${HEARTBEAT_AGE}s ago. Right-click a Finder image or restart Finder."
  fi
else
  warn "Finder Sync heartbeat not found yet: $HEARTBEAT_FILE"
fi

echo
echo "Queue state:"
if [[ -d "$JOB_DIR" ]]; then
  PENDING=0
  RETRYING=0
  PROCESSING=0
  FAILED=0

  for job_file in "$JOB_DIR"/*.json(N); do
    if grep -q '"nextAttemptAt"' "$job_file" 2>/dev/null; then
      RETRYING=$((RETRYING + 1))
    else
      PENDING=$((PENDING + 1))
    fi
  done
  for job_file in "$JOB_DIR"/*.processing(N); do
    PROCESSING=$((PROCESSING + 1))
  done
  for job_file in "$JOB_DIR"/*.failed(N); do
    FAILED=$((FAILED + 1))
  done

  echo "pending=$PENDING retrying=$RETRYING processing=$PROCESSING failed=$FAILED"
  if [[ "$FAILED" -gt 0 ]]; then
    warn "Queue has failed job(s). Recent failed files:"
    ls -t "$JOB_DIR"/*.failed(N) | head -n 5
  else
    pass "Queue has no failed jobs"
  fi
else
  warn "Queue directory not found yet: $JOB_DIR"
fi

echo
echo "Recent logs:"
if [[ -f "$FINDER_LOG" ]]; then
  echo
  echo "--- finder-sync.log ---"
  tail -n 12 "$FINDER_LOG"
else
  warn "Finder Sync log not found yet: $FINDER_LOG"
fi

if [[ -f "$APP_LOG" ]]; then
  echo
  echo "--- app.log ---"
  tail -n 12 "$APP_LOG"
elif [[ -f "$APP_LOG_FALLBACK" ]]; then
  echo
  echo "--- app.log fallback ---"
  tail -n 12 "$APP_LOG_FALLBACK"
else
  warn "App log not found yet: $APP_LOG"
fi

echo
echo "Summary: failures=$FAILURES warnings=$WARNINGS"
if [[ "$FAILURES" -gt 0 ]]; then
  echo "请把这个窗口里的全部文字发给开发者。"
  pause_if_needed
  exit 1
fi

echo "没有发现硬性安装问题。若顶层菜单不出现，请使用：右键图片 -> 快速操作/服务 -> ★ 同步进相册"
pause_if_needed
