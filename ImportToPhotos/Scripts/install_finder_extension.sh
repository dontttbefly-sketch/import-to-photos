#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/ImportToPhotos.app"
INSTALL_APP_DIR="/Applications/ImportToPhotos.app"
EXTENSION_DIR="$INSTALL_APP_DIR/Contents/PlugIns/SyncToPhotosFinder.appex"
EXTENSION_ID="local.import-to-photos.finder-sync"
SERVICE_SOURCE_DIR="$ROOT_DIR/Resources/ServiceWorkflow/同步进相册.workflow"
SERVICE_INSTALL_DIR="$HOME/Library/Services/★ 同步进相册.workflow"
OLD_SERVICE_INSTALL_DIR="$HOME/Library/Services/同步进相册.workflow"
LAUNCH_AGENT_SOURCE="$ROOT_DIR/Resources/LaunchAgent/local.import-to-photos.agent.plist"
LAUNCH_AGENT_INSTALL="$HOME/Library/LaunchAgents/local.import-to-photos.agent.plist"
LAUNCH_AGENT_LABEL="local.import-to-photos.agent"
GUI_DOMAIN="gui/$(id -u)"
RESTART_FINDER=0

for arg in "$@"; do
  case "$arg" in
    --restart-finder)
      RESTART_FINDER=1
      ;;
    --no-restart-finder)
      RESTART_FINDER=0
      ;;
    -h|--help)
      echo "usage: $0 [--restart-finder|--no-restart-finder]"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 64
      ;;
  esac
done

"$SCRIPT_DIR/build.sh"

ditto "$APP_DIR" "$INSTALL_APP_DIR"
touch "$INSTALL_APP_DIR"
mkdir -p "$HOME/Library/Services"
mkdir -p "$HOME/Library/LaunchAgents"
rm -rf "$OLD_SERVICE_INSTALL_DIR"
ditto "$SERVICE_SOURCE_DIR" "$SERVICE_INSTALL_DIR"
ditto "$LAUNCH_AGENT_SOURCE" "$LAUNCH_AGENT_INSTALL"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_APP_DIR" >/dev/null 2>&1 || true
pluginkit -a "$EXTENSION_DIR"
pluginkit -e use -i "$EXTENSION_ID"
launchctl bootout "$GUI_DOMAIN" "$LAUNCH_AGENT_INSTALL" >/dev/null 2>&1 || true
launchctl bootstrap "$GUI_DOMAIN" "$LAUNCH_AGENT_INSTALL"
launchctl kickstart -k "$GUI_DOMAIN/$LAUNCH_AGENT_LABEL"
/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
killall pbs >/dev/null 2>&1 || true

if [[ "$RESTART_FINDER" == "1" ]]; then
  killall Finder
else
  echo "Finder restart skipped. Run again with --restart-finder if the menu does not refresh."
fi

echo "Finder extension enabled: $EXTENSION_ID"
echo "Service workflow installed: $SERVICE_INSTALL_DIR"
echo "Login background agent installed: $LAUNCH_AGENT_INSTALL"
