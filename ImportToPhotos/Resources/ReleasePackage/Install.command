#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD_DIR="$SCRIPT_DIR/Payload"
APP_SOURCE="$PAYLOAD_DIR/Applications/ImportToPhotos.app"
APP_BINARY="$APP_SOURCE/Contents/MacOS/ImportToPhotos"
INSTALL_APP_DIR="/Applications/ImportToPhotos.app"
EXTENSION_DIR="$INSTALL_APP_DIR/Contents/PlugIns/SyncToPhotosFinder.appex"
EXTENSION_ID="local.import-to-photos.finder-sync"
SERVICE_SOURCE_DIR="$PAYLOAD_DIR/Resources/ServiceWorkflow/同步进相册.workflow"
SERVICE_INSTALL_DIR="$HOME/Library/Services/★ 同步进相册.workflow"
OLD_SERVICE_INSTALL_DIR="$HOME/Library/Services/同步进相册.workflow"
LAUNCH_AGENT_SOURCE="$PAYLOAD_DIR/Resources/LaunchAgent/local.import-to-photos.agent.plist"
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
    *)
      echo "Unknown option: $arg" >&2
      exit 64
      ;;
  esac
done

pause_if_needed() {
  if [[ "$NO_PAUSE" != "1" ]]; then
    echo
    read -r "?按回车键关闭这个窗口..."
  fi
}

finish() {
  local status=$?
  if [[ "$status" -ne 0 ]]; then
    echo
    echo "安装未完成。请双击 Doctor.command 查看诊断，或把这个窗口里的文字发给开发者。"
  fi
  pause_if_needed
  exit "$status"
}
trap finish EXIT

echo "ImportToPhotos GitHub Release 安装器"
echo

if [[ ! -x "$APP_BINARY" ]]; then
  echo "找不到安装包里的 app：$APP_SOURCE"
  exit 1
fi

APP_ARCHS="$(lipo -archs "$APP_BINARY" 2>/dev/null || true)"
MACHINE_ARCH="$(uname -m)"
if [[ -n "$APP_ARCHS" && " $APP_ARCHS " != *" $MACHINE_ARCH "* ]]; then
  echo "这个安装包的架构是：$APP_ARCHS"
  echo "当前 Mac 的架构是：$MACHINE_ARCH"
  echo "请换一个匹配架构的安装包。"
  exit 65
fi

echo "1/6 清理下载隔离标记，减少后续重复安全提示"
xattr -dr com.apple.quarantine "$SCRIPT_DIR" 2>/dev/null || true

echo "2/6 安装 app 到 /Applications"
ditto "$APP_SOURCE" "$INSTALL_APP_DIR"
touch "$INSTALL_APP_DIR"
xattr -dr com.apple.quarantine "$INSTALL_APP_DIR" 2>/dev/null || true

echo "3/6 安装右键服务兜底入口"
mkdir -p "$HOME/Library/Services"
ditto "$SERVICE_SOURCE_DIR" "$SERVICE_INSTALL_DIR"
if [[ -d "$OLD_SERVICE_INSTALL_DIR" ]]; then
  rm -rf "$OLD_SERVICE_INSTALL_DIR"
fi

echo "4/6 安装登录后台服务"
mkdir -p "$HOME/Library/LaunchAgents"
ditto "$LAUNCH_AGENT_SOURCE" "$LAUNCH_AGENT_INSTALL"

echo "5/6 注册 Finder Sync 扩展和后台服务"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_APP_DIR" >/dev/null 2>&1 || true
pluginkit -a "$EXTENSION_DIR"
pluginkit -e use -i "$EXTENSION_ID"
launchctl bootout "$GUI_DOMAIN" "$LAUNCH_AGENT_INSTALL" >/dev/null 2>&1 || true
launchctl bootstrap "$GUI_DOMAIN" "$LAUNCH_AGENT_INSTALL"
launchctl kickstart -k "$GUI_DOMAIN/$LAUNCH_AGENT_LABEL"

echo "6/6 刷新 Finder 和服务菜单"
/System/Library/CoreServices/pbs -flush >/dev/null 2>&1 || true
killall pbs >/dev/null 2>&1 || true
killall Finder >/dev/null 2>&1 || true

echo
echo "安装完成。第一次同步时，请允许 Photos 权限。"
echo "如果 Finder 顶层右键菜单没有出现，请用：右键图片 -> 快速操作/服务 -> ★ 同步进相册"
echo
"$SCRIPT_DIR/Doctor.command" --no-pause || true
