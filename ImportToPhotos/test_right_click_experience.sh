#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_SOURCE="$SCRIPT_DIR/ImportToPhotos.swift"
EXTENSION_SOURCE="$SCRIPT_DIR/FinderSyncExtension/FinderSyncExtension.swift"
SHARED_SOURCE="$SCRIPT_DIR/ImportToPhotosShared.swift"
ENTITLEMENTS="$SCRIPT_DIR/FinderSyncExtension/SyncToPhotosFinder.entitlements"
SERVICE_WORKFLOW="$SCRIPT_DIR/ServiceWorkflow/同步进相册.workflow"
LAUNCH_AGENT="$SCRIPT_DIR/LaunchAgent/local.import-to-photos.agent.plist"

NOTICE_BODY="$(awk '
  /private func showTimedNotice/ { in_body = 1 }
  in_body { print }
  in_body && /^}/ { exit }
' "$APP_SOURCE")"
SYMBOL_BODY="$(awk '
  /private func noticeSymbolName/ { in_body = 1 }
  in_body { print }
  in_body && /^}/ { exit }
' "$APP_SOURCE")"
TINT_BODY="$(awk '
  /private func noticeTintColor/ { in_body = 1 }
  in_body { print }
  in_body && /^}/ { exit }
' "$APP_SOURCE")"

if grep -Eq "NSAlert|runModal|addButton" <<< "$NOTICE_BODY"; then
  echo "showTimedNotice must use a non-clicking floating notice, not NSAlert/runModal/buttons." >&2
  exit 1
fi

grep -q "NSPanel" <<< "$NOTICE_BODY"
grep -q "NSVisualEffectView" <<< "$NOTICE_BODY"
grep -q "NSAnimationContext" <<< "$NOTICE_BODY"
grep -q "orderFrontRegardless" <<< "$NOTICE_BODY"
grep -q "asyncAfter" <<< "$NOTICE_BODY"
grep -q "systemSymbolName" <<< "$NOTICE_BODY"
grep -q "ofSize: 13" <<< "$NOTICE_BODY"

if grep -q "ofSize: 20" <<< "$NOTICE_BODY"; then
  echo "showTimedNotice should use compact toast typography, not 20pt text." >&2
  exit 1
fi

grep -q 'return "checkmark.circle"' <<< "$SYMBOL_BODY"
grep -q 'return "xmark.circle"' <<< "$SYMBOL_BODY"

if grep -q "checkmark.circle.fill" <<< "$SYMBOL_BODY"; then
  echo "Success toast should use a transparent outline checkmark, not a filled checkmark." >&2
  exit 1
fi

if grep -q "xmark.circle.fill" <<< "$SYMBOL_BODY"; then
  echo "Failure toast should use a transparent outline xmark, not a filled xmark." >&2
  exit 1
fi

grep -q "return .white" <<< "$TINT_BODY"

if grep -q "systemGreen" <<< "$TINT_BODY"; then
  echo "Success toast should use a white checkmark, not a green one." >&2
  exit 1
fi

if grep -q "systemRed" <<< "$TINT_BODY"; then
  echo "Failure toast should use a white xmark, not a red one." >&2
  exit 1
fi

if grep -q "Library.*Logs" "$EXTENSION_SOURCE"; then
  echo "Finder Sync logging should not write directly to ~/Library/Logs; use OSLog and the extension container." >&2
  exit 1
fi

if grep -Eq "^[[:space:]]*home," "$EXTENSION_SOURCE"; then
  echo "Finder Sync should not monitor the whole home directory." >&2
  exit 1
fi

if grep -q "homeDirectoryForCurrentUser" "$EXTENSION_SOURCE"; then
  echo "Finder Sync should resolve the real user home, not the sandbox container home." >&2
  exit 1
fi

grep -q "realUserHomeDirectory" "$EXTENSION_SOURCE"
grep -q "getpwuid" "$EXTENSION_SOURCE"

for expected in "Pictures" "Desktop" "Downloads" "上传"; do
  if ! grep -q "$expected" "$EXTENSION_SOURCE"; then
    echo "Finder Sync watched directories should include $expected." >&2
    exit 1
  fi
done

grep -q "targetedURL" "$EXTENSION_SOURCE"
grep -Eq "OSLog|Logger" "$EXTENSION_SOURCE"
grep -q "applicationSupportDirectory" "$EXTENSION_SOURCE"
grep -q "finder-sync.log" "$EXTENSION_SOURCE"
grep -q "logFinderSync" "$EXTENSION_SOURCE"
grep -q "beginObservingDirectory" "$EXTENSION_SOURCE"
grep -q "endObservingDirectory" "$EXTENSION_SOURCE"
grep -q "requestBadgeIdentifier" "$EXTENSION_SOURCE"
grep -q "setBadgeImage" "$EXTENSION_SOURCE"
grep -q "setBadgeIdentifier" "$EXTENSION_SOURCE"
grep -q "eligible-image" "$EXTENSION_SOURCE"
grep -q "refreshEligibleBadges" "$EXTENSION_SOURCE"
grep -q "contentsOfDirectory" "$EXTENSION_SOURCE"
grep -q "toolbarItemName" "$EXTENSION_SOURCE"
grep -q "toolbarItemToolTip" "$EXTENSION_SOURCE"
grep -q "toolbarItemImage" "$EXTENSION_SOURCE"
grep -q "toolbarItemMenu" "$EXTENSION_SOURCE"
grep -q "未选中图片" "$EXTENSION_SOURCE"
grep -q "fallbackPaths" "$EXTENSION_SOURCE"
grep -q "★ 同步进相册" "$EXTENSION_SOURCE"
grep -q "enqueueSyncJob" "$EXTENSION_SOURCE"
grep -q "FinderSyncQueuedJob" "$EXTENSION_SOURCE"
grep -q "finderSyncJobDirectory" "$EXTENSION_SOURCE"
grep -q "DistributedNotificationCenter" "$EXTENSION_SOURCE"
grep -q "sync job queued" "$EXTENSION_SOURCE"
grep -q "sync job enqueue failed" "$EXTENSION_SOURCE"

if grep -q "Process()" "$EXTENSION_SOURCE"; then
  echo "Finder Sync should enqueue work for the background agent, not launch a sandbox-inherited child process." >&2
  exit 1
fi

grep -q "FinderSyncQueuedJob" "$SHARED_SOURCE"
grep -q "finderSyncJobNotificationName" "$SHARED_SOURCE"
grep -q "finderSyncJobDirectory" "$SHARED_SOURCE"
grep -q "finderSyncSharedSupportDirectory" "$SHARED_SOURCE"
grep -q "local.import-to-photos.finder-sync" "$SHARED_SOURCE"
grep -q "Containers" "$SHARED_SOURCE"
grep -q "Application Support" "$SHARED_SOURCE"
grep -q "jobs" "$SHARED_SOURCE"
if grep -q "/tmp/local.import-to-photos/jobs" "$SHARED_SOURCE" "$EXTENSION_SOURCE" "$APP_SOURCE"; then
  echo "Finder Sync job queue must live in the extension container, not /tmp." >&2
  exit 1
fi
grep -q "processPendingFinderSyncJobs" "$APP_SOURCE"
grep -q "agent processing sync job" "$APP_SOURCE"
grep -q "Timer.scheduledTimer" "$APP_SOURCE"
grep -q "terminateAfterClose: false" "$APP_SOURCE"
grep -q "app.log" "$APP_SOURCE"

if grep -q "guard FileManager.default.fileExists" "$SHARED_SOURCE"; then
  echo "Finder Sync eligibility should not hide menu just because sandboxed fileExists fails." >&2
  exit 1
fi

for expected in "/Desktop/" "/Pictures/" "/Downloads/"; do
  if ! grep -q "$expected" "$ENTITLEMENTS"; then
    echo "Finder Sync entitlements should allow read-only access to $expected." >&2
    exit 1
  fi
done

test -f "$SERVICE_WORKFLOW/Contents/Info.plist"
test -f "$SERVICE_WORKFLOW/Contents/Resources/document.wflow"
plutil -lint "$SERVICE_WORKFLOW/Contents/Info.plist" "$SERVICE_WORKFLOW/Contents/Resources/document.wflow" >/dev/null
grep -q "★ 同步进相册" "$SERVICE_WORKFLOW/Contents/Info.plist"
grep -q "★ 同步进相册.workflow" "$SCRIPT_DIR/install_finder_extension.sh"
grep -q "OLD_SERVICE_INSTALL_DIR" "$SCRIPT_DIR/install_finder_extension.sh"
grep -q "/Applications/ImportToPhotos.app/Contents/MacOS/ImportToPhotos --sync-copy" "$SERVICE_WORKFLOW/Contents/Resources/document.wflow"
grep -q "<key>serviceApplicationBundleID</key>" "$SERVICE_WORKFLOW/Contents/Resources/document.wflow"
if grep -q "<string>com.apple.finder</string>" "$SERVICE_WORKFLOW/Contents/Resources/document.wflow"; then
  echo "Workflow should not be pinned to Finder only; match system Quick Actions metadata." >&2
  exit 1
fi

test -f "$LAUNCH_AGENT"
plutil -lint "$LAUNCH_AGENT" >/dev/null
grep -q -- "--background-agent" "$APP_SOURCE"
grep -q -- "--background-agent" "$LAUNCH_AGENT"
grep -q "launchctl bootstrap" "$SCRIPT_DIR/install_finder_extension.sh"
grep -q "launchctl kickstart" "$SCRIPT_DIR/install_finder_extension.sh"
