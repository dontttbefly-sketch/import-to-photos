#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/ImportToPhotos.app"
APP_BINARY="$APP_DIR/Contents/MacOS/ImportToPhotos"
APP_INFO_PLIST="$ROOT_DIR/Resources/App/Info.plist"
TEMPLATE_DIR="$ROOT_DIR/Resources/ReleasePackage"
INSTALLER_SCRIPT_SOURCE="$ROOT_DIR/Resources/InstallerScripts/postinstall"
SERVICE_SOURCE_DIR="$ROOT_DIR/Resources/ServiceWorkflow/同步进相册.workflow"
LAUNCH_AGENT_SOURCE="$ROOT_DIR/Resources/LaunchAgent/local.import-to-photos.agent.plist"
SKIP_BUILD=0
UNIVERSAL=0
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_INFO_PLIST")"

while [[ "$#" -gt 0 ]]; do
  arg="$1"
  case "$arg" in
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --universal)
      UNIVERSAL=1
      shift
      ;;
    --version)
      if [[ "$#" -lt 2 ]]; then
        echo "--version requires a value" >&2
        exit 64
      fi
      VERSION="$2"
      shift 2
      ;;
    --version=*)
      VERSION="${arg#--version=}"
      shift
      ;;
    -h|--help)
      echo "usage: $0 [--skip-build] [--universal] [--version VERSION]"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 64
      ;;
  esac
done

if [[ "$SKIP_BUILD" != "1" ]]; then
  if [[ "$UNIVERSAL" == "1" ]]; then
    "$SCRIPT_DIR/build.sh" --universal
  else
    "$SCRIPT_DIR/build.sh"
  fi
fi

if [[ ! -x "$APP_BINARY" ]]; then
  echo "Missing app binary: $APP_BINARY" >&2
  exit 1
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
CPU_ARCH="$(uname -m)"
APP_ARCHS="$(lipo -archs "$APP_BINARY" 2>/dev/null || true)"
ARCH_LABEL="$(tr ' ' '-' <<< "$APP_ARCHS")"
if [[ "$APP_ARCHS" == *"arm64"* && "$APP_ARCHS" == *"x86_64"* ]]; then
  ARCH_LABEL="universal"
fi
if [[ -z "$ARCH_LABEL" ]]; then
  ARCH_LABEL="$CPU_ARCH"
fi
PACKAGE_NAME="ImportToPhotos-v$VERSION-$ARCH_LABEL"
PACKAGE_DIR="$ROOT_DIR/dist/$PACKAGE_NAME"
PKG_PATH="$PACKAGE_DIR/Install ImportToPhotos.pkg"
DMG_PATH="$ROOT_DIR/dist/$PACKAGE_NAME.dmg"
if [[ -e "$PACKAGE_DIR" || -e "$DMG_PATH" ]]; then
  PACKAGE_NAME="ImportToPhotos-v$VERSION-$ARCH_LABEL-$TIMESTAMP"
  PACKAGE_DIR="$ROOT_DIR/dist/$PACKAGE_NAME"
  PKG_PATH="$PACKAGE_DIR/Install ImportToPhotos.pkg"
  DMG_PATH="$ROOT_DIR/dist/$PACKAGE_NAME.dmg"
fi

mkdir -p \
  "$PACKAGE_DIR/pkg-root/Applications" \
  "$PACKAGE_DIR/pkg-scripts/Resources/ServiceWorkflow" \
  "$PACKAGE_DIR/pkg-scripts/Resources/LaunchAgent" \
  "$PACKAGE_DIR/dmg-root"

ditto "$APP_DIR" "$PACKAGE_DIR/pkg-root/Applications/ImportToPhotos.app"
rm -f "$PACKAGE_DIR/pkg-root/Applications/ImportToPhotos.app/Contents/Resources/DefaultImportFolder.txt"
ditto "$SERVICE_SOURCE_DIR" "$PACKAGE_DIR/pkg-scripts/Resources/ServiceWorkflow/同步进相册.workflow"
ditto "$LAUNCH_AGENT_SOURCE" "$PACKAGE_DIR/pkg-scripts/Resources/LaunchAgent/local.import-to-photos.agent.plist"
ditto "$INSTALLER_SCRIPT_SOURCE" "$PACKAGE_DIR/pkg-scripts/postinstall"
chmod +x "$PACKAGE_DIR/pkg-scripts/postinstall"
ditto "$TEMPLATE_DIR/README-先双击我.md" "$PACKAGE_DIR/dmg-root/README-先读我.md"

APP_BINARY_TYPE="$(file "$APP_BINARY" | head -n 1 | sed 's/^[^:]*: //')"

{
  echo "PACKAGE_NAME=$PACKAGE_NAME"
  echo "VERSION=$VERSION"
  echo "CREATED_AT=$TIMESTAMP"
  echo "DISTRIBUTION=github-release"
  echo "FORMAT=dmg-pkg"
  echo "CPU_ARCH=$CPU_ARCH"
  echo "APP_ARCHS=$APP_ARCHS"
  echo "APP_BINARY_TYPE=$APP_BINARY_TYPE"
  echo "SIGNING=adhoc"
  echo "PKG_SIGNING=unsigned"
  echo "NOTARIZED=no"
} > "$PACKAGE_DIR/package-info.txt"

pkgbuild \
  --root "$PACKAGE_DIR/pkg-root" \
  --scripts "$PACKAGE_DIR/pkg-scripts" \
  --identifier "local.import-to-photos.installer" \
  --version "$VERSION" \
  --install-location "/" \
  --ownership recommended \
  "$PKG_PATH"

ditto "$PKG_PATH" "$PACKAGE_DIR/dmg-root/Install ImportToPhotos.pkg"
ditto "$PACKAGE_DIR/package-info.txt" "$PACKAGE_DIR/dmg-root/package-info.txt"
hdiutil create \
  -volname "ImportToPhotos $VERSION" \
  -srcfolder "$PACKAGE_DIR/dmg-root" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "PACKAGE_DIR=$PACKAGE_DIR"
echo "PKG_PATH=$PKG_PATH"
echo "DMG_PATH=$DMG_PATH"
