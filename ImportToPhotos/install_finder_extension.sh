#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/ImportToPhotos.app"
INSTALL_APP_DIR="/Applications/ImportToPhotos.app"
EXTENSION_DIR="$INSTALL_APP_DIR/Contents/PlugIns/SyncToPhotosFinder.appex"
EXTENSION_ID="local.import-to-photos.finder-sync"
SERVICE_SOURCE_DIR="$SCRIPT_DIR/ServiceWorkflow/同步进相册.workflow"
SERVICE_INSTALL_DIR="$HOME/Library/Services/★ 同步进相册.workflow"
OLD_SERVICE_INSTALL_DIR="$HOME/Library/Services/同步进相册.workflow"
LAUNCH_AGENT_SOURCE="$SCRIPT_DIR/LaunchAgent/local.import-to-photos.agent.plist"
LAUNCH_AGENT_INSTALL="$HOME/Library/LaunchAgents/local.import-to-photos.agent.plist"
LAUNCH_AGENT_LABEL="local.import-to-photos.agent"
GUI_DOMAIN="gui/$(id -u)"

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

killall Finder

echo "Finder extension enabled: $EXTENSION_ID"
echo "Service workflow installed: $SERVICE_INSTALL_DIR"
echo "Login background agent installed: $LAUNCH_AGENT_INSTALL"
