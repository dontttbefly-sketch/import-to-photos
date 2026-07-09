#!/bin/zsh
set -euo pipefail

APP_DIR="/Applications/ImportToPhotos.app"
EXTENSION_ID="local.import-to-photos.finder-sync"
SERVICE_INSTALL_DIR="$HOME/Library/Services/★ 同步进相册.workflow"
OLD_SERVICE_INSTALL_DIR="$HOME/Library/Services/同步进相册.workflow"
LAUNCH_AGENT_INSTALL="$HOME/Library/LaunchAgents/local.import-to-photos.agent.plist"
LAUNCH_AGENT_LABEL="local.import-to-photos.agent"
GUI_DOMAIN="gui/$(id -u)"
NO_PAUSE=0

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

trap pause_if_needed EXIT

echo "ImportToPhotos 卸载器"
echo

launchctl bootout "$GUI_DOMAIN" "$LAUNCH_AGENT_INSTALL" >/dev/null 2>&1 || true
pluginkit -e ignore -i "$EXTENSION_ID" >/dev/null 2>&1 || true

rm -rf "$SERVICE_INSTALL_DIR"
rm -rf "$OLD_SERVICE_INSTALL_DIR"
rm -f "$LAUNCH_AGENT_INSTALL"

if [[ -d "$APP_DIR" ]]; then
  /usr/bin/osascript <<'OSA'
do shell script "/bin/rm -rf /Applications/ImportToPhotos.app" with administrator privileges
OSA
fi

/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
killall pbs >/dev/null 2>&1 || true
killall Finder >/dev/null 2>&1 || true

echo "已卸载 app、右键服务和登录后台服务。"
echo "日志保留在：$HOME/Library/Application Support/ImportToPhotos"
