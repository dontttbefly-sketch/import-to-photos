#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_SOURCE_DIR="$ROOT_DIR/Sources/App"
EXTENSION_SOURCE_DIR="$ROOT_DIR/Sources/FinderSyncExtension"
SHARED_SOURCE_DIR="$ROOT_DIR/Sources/Shared"
NOTICE_SOURCE="$APP_SOURCE_DIR/NoticePresenter.swift"
NOTICE_KIND_SOURCE="$APP_SOURCE_DIR/NoticeKind.swift"
AGENT_SOURCE="$APP_SOURCE_DIR/BackgroundJobAgent.swift"
FINDER_COPY_SOURCE="$APP_SOURCE_DIR/FinderSyncCopyService.swift"
EXTENSION_SOURCE="$EXTENSION_SOURCE_DIR/FinderSyncExtension.swift"
MENU_SOURCE="$EXTENSION_SOURCE_DIR/FinderMenuController.swift"
BADGE_SOURCE="$EXTENSION_SOURCE_DIR/FinderBadgeController.swift"
LOGGER_SOURCE="$EXTENSION_SOURCE_DIR/FinderSyncLogger.swift"
CONFIG_SOURCE="$SHARED_SOURCE_DIR/AppConfig.swift"
IMAGE_POLICY_SOURCE="$SHARED_SOURCE_DIR/ImageTypePolicy.swift"
JOB_QUEUE_SOURCE="$SHARED_SOURCE_DIR/FinderSyncJobQueue.swift"
JOB_SOURCE="$SHARED_SOURCE_DIR/FinderSyncJob.swift"
ENTITLEMENTS="$ROOT_DIR/Resources/FinderSyncExtension/SyncToPhotosFinder.entitlements"
APP_INFO_PLIST="$ROOT_DIR/Resources/App/Info.plist"
EXTENSION_INFO_PLIST="$ROOT_DIR/Resources/FinderSyncExtension/Info.plist"
SERVICE_WORKFLOW="$ROOT_DIR/Resources/ServiceWorkflow/同步进相册.workflow"
LAUNCH_AGENT="$ROOT_DIR/Resources/LaunchAgent/local.import-to-photos.agent.plist"
ROOT_README="$ROOT_DIR/../README.md"

NOTICE_BODY="$(awk '
  /static func showTimedNotice/ { in_body = 1 }
  in_body { print }
  in_body && /^}/ { exit }
' "$NOTICE_SOURCE")"
for expected_file in \
  "$APP_SOURCE_DIR/AppDelegate.swift" \
  "$APP_SOURCE_DIR/AppLogger.swift" \
  "$APP_SOURCE_DIR/CommandLineOptions.swift" \
  "$APP_SOURCE_DIR/FinderSyncCopyService.swift" \
  "$APP_SOURCE_DIR/ImageScanner.swift" \
  "$APP_SOURCE_DIR/NoticeKind.swift" \
  "$APP_SOURCE_DIR/PhotosImporter.swift" \
  "$APP_SOURCE_DIR/ImportToPhotosMain.swift" \
  "$SHARED_SOURCE_DIR/AppConfig.swift" \
  "$SHARED_SOURCE_DIR/FileLogWriter.swift" \
  "$SHARED_SOURCE_DIR/FinderSyncJob.swift" \
  "$SHARED_SOURCE_DIR/FinderSyncJobQueue.swift" \
  "$SHARED_SOURCE_DIR/ImageTypePolicy.swift" \
  "$SHARED_SOURCE_DIR/UploadedMarkerStore.swift" \
  "$EXTENSION_SOURCE_DIR/FinderBadgeController.swift" \
  "$EXTENSION_SOURCE_DIR/FinderMenuController.swift" \
  "$EXTENSION_SOURCE_DIR/FinderSyncExtension.swift" \
  "$EXTENSION_SOURCE_DIR/FinderSyncLogger.swift"; do
  test -f "$expected_file"
done

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
grep -q "enum NoticeKind" "$NOTICE_KIND_SOURCE"
grep -q "case synced" "$NOTICE_KIND_SOURCE"
grep -q "case alreadySynced" "$NOTICE_KIND_SOURCE"
grep -q "case needsAuthorization" "$NOTICE_KIND_SOURCE"
grep -q "case syncFailed" "$NOTICE_KIND_SOURCE"
grep -q "case partialFailure" "$NOTICE_KIND_SOURCE"
grep -q "symbolName" "$NOTICE_KIND_SOURCE"
grep -q "tintColor" "$NOTICE_KIND_SOURCE"

if grep -q "ofSize: 20" <<< "$NOTICE_BODY"; then
  echo "showTimedNotice should use compact toast typography, not 20pt text." >&2
  exit 1
fi

grep -q 'return "checkmark.circle"' "$NOTICE_KIND_SOURCE"
grep -q 'return "xmark.circle"' "$NOTICE_KIND_SOURCE"

if grep -q "noticeSymbolName(for: message)" "$NOTICE_SOURCE"; then
  echo "Toast icons should be driven by NoticeKind, not localized strings." >&2
  exit 1
fi

if grep -q "checkmark.circle.fill" "$NOTICE_KIND_SOURCE"; then
  echo "Success toast should use a transparent outline checkmark, not a filled checkmark." >&2
  exit 1
fi

if grep -q "xmark.circle.fill" "$NOTICE_KIND_SOURCE"; then
  echo "Failure toast should use a transparent outline xmark, not a filled xmark." >&2
  exit 1
fi

grep -q "return .white" "$NOTICE_KIND_SOURCE"

if grep -q "systemGreen" "$NOTICE_KIND_SOURCE"; then
  echo "Success toast should use a white checkmark, not a green one." >&2
  exit 1
fi

if grep -q "systemRed" "$NOTICE_KIND_SOURCE"; then
  echo "Failure toast should use a white xmark, not a red one." >&2
  exit 1
fi

if grep -R -q "Library.*Logs" "$EXTENSION_SOURCE_DIR"; then
  echo "Finder Sync logging should not write directly to ~/Library/Logs; use OSLog and the extension container." >&2
  exit 1
fi

if grep -R -q "homeDirectoryForCurrentUser" "$EXTENSION_SOURCE_DIR" "$SHARED_SOURCE_DIR"; then
  echo "Finder Sync should resolve the real user home, not the sandbox container home." >&2
  exit 1
fi

grep -q "realUserHomeDirectory" "$CONFIG_SOURCE"
grep -q "getpwuid" "$CONFIG_SOURCE"
grep -q "AppConfig.realUserHomeDirectory" "$EXTENSION_SOURCE"
grep -q "monitoredDirectories" "$EXTENSION_SOURCE"
grep -q "Desktop" "$EXTENSION_SOURCE"
grep -q "Downloads" "$EXTENSION_SOURCE"
grep -q "Pictures" "$EXTENSION_SOURCE"
grep -q "Documents" "$EXTENSION_SOURCE"
grep -q "standardHomeChild" "$EXTENSION_SOURCE"

if grep -R -q "refreshEligibleBadges" "$EXTENSION_SOURCE_DIR"; then
  echo "Finder Sync should not eagerly refresh badges by scanning opened directories." >&2
  exit 1
fi

if grep -R -q "contentsOfDirectory" "$EXTENSION_SOURCE_DIR"; then
  echo "Finder Sync should not enumerate opened directories while monitoring the whole home directory." >&2
  exit 1
fi

grep -q "targetedURL" "$EXTENSION_SOURCE"
grep -Eq "OSLog|Logger" "$LOGGER_SOURCE"
grep -q "applicationSupportDirectory" "$LOGGER_SOURCE"
grep -q "finder-sync.log" "$LOGGER_SOURCE"
grep -q "FileLogWriter" "$SHARED_SOURCE_DIR/FileLogWriter.swift"
grep -q "FileLogWriter.append" "$APP_SOURCE_DIR/AppLogger.swift"
grep -q "FileLogWriter.append" "$LOGGER_SOURCE"
grep -q "static func write" "$SHARED_SOURCE_DIR/FileLogWriter.swift"
grep -q "FileLogWriter.write" "$LOGGER_SOURCE"
grep -q "IMPORT_TO_PHOTOS_VERBOSE_FINDER_SYNC" "$LOGGER_SOURCE"
grep -q "flock(" "$SHARED_SOURCE_DIR/FileLogWriter.swift"
grep -q "FinderSyncLogger.isVerbose" "$BADGE_SOURCE"
grep -q "FinderSyncLogger.log" "$EXTENSION_SOURCE"
grep -q "beginObservingDirectory" "$EXTENSION_SOURCE"
grep -q "endObservingDirectory" "$EXTENSION_SOURCE"
grep -q "requestBadgeIdentifier" "$EXTENSION_SOURCE"
grep -q "setBadgeImage" "$BADGE_SOURCE"
grep -q "setBadgeIdentifier" "$BADGE_SOURCE"
grep -q "eligible-image" "$BADGE_SOURCE"
grep -q "toolbarItemName" "$EXTENSION_SOURCE"
grep -q "toolbarItemToolTip" "$EXTENSION_SOURCE"
grep -q "toolbarItemImage" "$EXTENSION_SOURCE"
grep -q "toolbarItemMenu" "$MENU_SOURCE"
grep -q "未选中图片" "$MENU_SOURCE"
grep -q "fallbackPaths" "$EXTENSION_SOURCE"
grep -q "★ 同步进相册" "$EXTENSION_SOURCE"
grep -q "enqueueSyncJob" "$EXTENSION_SOURCE"
grep -q "FinderSyncQueuedJob" "$JOB_SOURCE"
grep -q "finderSyncJobDirectory" "$CONFIG_SOURCE"
grep -q "DistributedNotificationCenter" "$EXTENSION_SOURCE"
grep -q "sync job queued" "$EXTENSION_SOURCE"
grep -q "sync job enqueue failed" "$EXTENSION_SOURCE"

if grep -R -q "Process()" "$EXTENSION_SOURCE_DIR"; then
  echo "Finder Sync should enqueue work for the background agent, not launch a sandbox-inherited child process." >&2
  exit 1
fi

grep -q "FinderSyncQueuedJob" "$JOB_SOURCE"
grep -q "finderSyncJobNotificationName" "$CONFIG_SOURCE"
grep -q "finderSyncJobDirectory" "$CONFIG_SOURCE"
grep -q "finderSyncSharedSupportDirectory" "$CONFIG_SOURCE"
grep -q "finderSyncHeartbeatURL" "$CONFIG_SOURCE"
grep -q "isFinderSyncExcludedPath" "$IMAGE_POLICY_SOURCE"
grep -q "finderSyncExcludedPathComponents" "$IMAGE_POLICY_SOURCE"
grep -q "finderSyncExcludedHomeChildren" "$IMAGE_POLICY_SOURCE"
for expected in ".git" "node_modules" ".venv" "venv" "__pycache__" ".build" "build" "DerivedData" ".cache" ".npm" ".pnpm-store" ".swiftpm" ".gradle" "Pods" "Library" ".Trash" "Applications"; do
  if ! grep -q "$expected" "$IMAGE_POLICY_SOURCE"; then
    echo "Finder Sync exclusions should include $expected." >&2
    exit 1
  fi
done
grep -q "local.import-to-photos.finder-sync" "$CONFIG_SOURCE"
grep -q "Containers" "$CONFIG_SOURCE"
grep -q "Application Support" "$CONFIG_SOURCE"
grep -q "jobs" "$CONFIG_SOURCE"
if grep -R -q "/tmp/local.import-to-photos/jobs" "$SHARED_SOURCE_DIR" "$EXTENSION_SOURCE_DIR" "$APP_SOURCE_DIR"; then
  echo "Finder Sync job queue must live in the extension container, not /tmp." >&2
  exit 1
fi
grep -q "claimNextJob" "$JOB_QUEUE_SOURCE"
grep -q "appendingPathExtension(\"processing\")" "$JOB_QUEUE_SOURCE"
grep -q "complete(_ claimedJob" "$JOB_QUEUE_SOURCE"
grep -q "fail(_ claimedJob" "$JOB_QUEUE_SOURCE"
grep -q "retryLater(_ claimedJob" "$JOB_QUEUE_SOURCE"
grep -q "attemptCount" "$JOB_SOURCE"
grep -q "nextAttemptAt" "$JOB_SOURCE"
grep -q "lastError" "$JOB_SOURCE"
grep -q "maxAttempts" "$JOB_SOURCE"
grep -q "withStagedPaths" "$JOB_SOURCE"
grep -q "retryBackoff" "$JOB_QUEUE_SOURCE"
grep -q "QueueResolution" "$FINDER_COPY_SOURCE"
grep -q "retryLater(paths:" "$FINDER_COPY_SOURCE"
grep -q "retryPaths" "$FINDER_COPY_SOURCE"
grep -q "retryStagedPaths" "$FINDER_COPY_SOURCE"
grep -q "ImportFailureKind" "$APP_SOURCE_DIR/PhotosImporter.swift" "$FINDER_COPY_SOURCE"
if grep -q "isPermanentFailureMessage" "$FINDER_COPY_SOURCE"; then
  echo "Queue decisions should use ImportFailureKind, not localized/error-message string matching." >&2
  exit 1
fi
grep -q "retryLater" "$AGENT_SOURCE"
grep -q "enqueueRetryJob" "$AGENT_SOURCE"
grep -q "stagedPaths" "$AGENT_SOURCE"
grep -q "recoverStaleProcessingJobs" "$JOB_QUEUE_SOURCE"
grep -q "staleProcessingInterval" "$JOB_QUEUE_SOURCE"
grep -q "IMPORT_TO_PHOTOS_JOB_DIR" "$CONFIG_SOURCE"
grep -q "IMPORT_TO_PHOTOS_ENABLE_TEST_HOOKS" "$APP_SOURCE_DIR/ImportToPhotosMain.swift"
grep -q "TEST_HOOKS_DISABLED" "$APP_SOURCE_DIR/ImportToPhotosMain.swift"
grep -q "processPendingFinderSyncJobs" "$AGENT_SOURCE"
grep -q "agent processing sync job" "$AGENT_SOURCE"
grep -q "Timer.scheduledTimer" "$AGENT_SOURCE"
grep -q "terminateAfterClose: false" "$AGENT_SOURCE"
grep -q "jobQueue.complete" "$AGENT_SOURCE"
grep -q "jobQueue.fail" "$AGENT_SOURCE"
grep -q "app.log" "$CONFIG_SOURCE"
grep -q "appLogURL" "$CONFIG_SOURCE"
grep -q "AppConfig.appLogURL" "$APP_SOURCE_DIR/AppLogger.swift"
if grep -q 'URL(fileURLWithPath: "/tmp/local.import-to-photos"' "$APP_SOURCE_DIR/AppLogger.swift"; then
  echo "AppLogger should write to Application Support; /tmp should only be a Doctor fallback." >&2
  exit 1
fi
grep -q "prepareCopyJobs" "$FINDER_COPY_SOURCE"
grep -q "runCopyTest" "$FINDER_COPY_SOURCE"
grep -q "finderSyncKeepCopyEnabled" "$FINDER_COPY_SOURCE"
grep -q "IMPORT_TO_PHOTOS_KEEP_COPY" "$CONFIG_SOURCE"
grep -q "settings.env" "$CONFIG_SOURCE"
grep -q "backupURL: source" "$FINDER_COPY_SOURCE"
grep -q "USING_SOURCE" "$FINDER_COPY_SOURCE"
grep -q "sourceURL.path != job.backupURL.path" "$FINDER_COPY_SOURCE"
grep -q "copyItem" "$FINDER_COPY_SOURCE"
if ! grep -q "guard AppConfig.finderSyncKeepCopyEnabled()" "$FINDER_COPY_SOURCE"; then
  echo "Finder sync copies must be guarded behind the explicit keep-copy setting." >&2
  exit 1
fi
if grep -q "MARKED_BACKUP" "$FINDER_COPY_SOURCE" &&
   ! grep -q "sourceURL.path != job.backupURL.path" "$FINDER_COPY_SOURCE"; then
  echo "Backup marker writes must stay guarded for optional future keep-copy behavior." >&2
  exit 1
fi
grep -q "ImportSupportStatus" "$IMAGE_POLICY_SOURCE"
grep -q "possibleRaw" "$IMAGE_POLICY_SOURCE"
grep -q "supportSummary" "$IMAGE_POLICY_SOURCE"
grep -q "writeHeartbeat" "$LOGGER_SOURCE"
grep -q "Finder Sync heartbeat" "$ROOT_DIR/Resources/ReleasePackage/Doctor.command"
grep -q "Queue state:" "$ROOT_DIR/Resources/ReleasePackage/Doctor.command"
grep -q 'FINDER_LOG="$SHARED_SUPPORT_DIR/finder-sync.log"' "$ROOT_DIR/Resources/ReleasePackage/Doctor.command"
if grep -q "APP_LOG_FALLBACK" "$ROOT_DIR/Resources/ReleasePackage/Doctor.command"; then
  echo "Doctor should report the current app log path, not a stale /tmp fallback." >&2
  exit 1
fi
grep -q 'rm -rf "$APP_DIR"' "$SCRIPT_DIR/build.sh"

if grep -q "guard FileManager.default.fileExists" "$IMAGE_POLICY_SOURCE"; then
  echo "Finder Sync eligibility should not hide menu just because sandboxed fileExists fails." >&2
  exit 1
fi

grep -q "<string>/</string>" "$ENTITLEMENTS"

test -f "$SERVICE_WORKFLOW/Contents/Info.plist"
test -f "$SERVICE_WORKFLOW/Contents/Resources/document.wflow"
plutil -lint "$SERVICE_WORKFLOW/Contents/Info.plist" "$SERVICE_WORKFLOW/Contents/Resources/document.wflow" >/dev/null
grep -q "★ 同步进相册" "$SERVICE_WORKFLOW/Contents/Info.plist"
grep -q "★ 同步进相册.workflow" "$SCRIPT_DIR/install_finder_extension.sh"
grep -q "OLD_SERVICE_INSTALL_DIR" "$SCRIPT_DIR/install_finder_extension.sh"
grep -q "/Applications/ImportToPhotos.app/Contents/MacOS/ImportToPhotos --sync-import" "$SERVICE_WORKFLOW/Contents/Resources/document.wflow"
grep -q -- "--sync-import" "$APP_SOURCE_DIR/CommandLineOptions.swift"
grep -q -- "--sync-copy" "$APP_SOURCE_DIR/CommandLineOptions.swift"
if grep -q -- "--sync-copy" "$SERVICE_WORKFLOW/Contents/Resources/document.wflow"; then
  echo "Service workflow should use --sync-import; --sync-copy is only a legacy compatibility alias." >&2
  exit 1
fi
grep -q "<key>serviceApplicationBundleID</key>" "$SERVICE_WORKFLOW/Contents/Resources/document.wflow"
if grep -q "<string>com.apple.finder</string>" "$SERVICE_WORKFLOW/Contents/Resources/document.wflow"; then
  echo "Workflow should not be pinned to Finder only; match system Quick Actions metadata." >&2
  exit 1
fi

test -f "$LAUNCH_AGENT"
plutil -lint "$LAUNCH_AGENT" >/dev/null
APP_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_INFO_PLIST")"
EXTENSION_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$EXTENSION_INFO_PLIST")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_INFO_PLIST")"
EXTENSION_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$EXTENSION_INFO_PLIST")"
test "$APP_VERSION" = "$EXTENSION_VERSION"
test "$APP_BUILD" = "$EXTENSION_BUILD"
grep -q -- "--background-agent" "$APP_SOURCE_DIR/CommandLineOptions.swift"
grep -q -- "--background-agent" "$LAUNCH_AGENT"
grep -q "launchctl bootstrap" "$SCRIPT_DIR/install_finder_extension.sh"
grep -q "launchctl kickstart" "$SCRIPT_DIR/install_finder_extension.sh"
grep -q -- "--restart-finder" "$SCRIPT_DIR/install_finder_extension.sh"
grep -q "RESTART_FINDER" "$SCRIPT_DIR/install_finder_extension.sh"

grep -q "./ImportToPhotos/Scripts/install_finder_extension.sh" "$ROOT_README"
grep -q "直接把所选图片导入 Photos" "$ROOT_README"
grep -q "IMPORT_TO_PHOTOS_KEEP_COPY=1" "$ROOT_README"
grep -q "settings.env" "$ROOT_README"
grep -q "桌面" "$ROOT_README"
grep -q "快速操作/服务" "$ROOT_README"
if grep -q "./ImportToPhotos/install_finder_extension.sh" "$ROOT_README"; then
  echo "Root README should not reference the old install_finder_extension.sh path." >&2
  exit 1
fi
