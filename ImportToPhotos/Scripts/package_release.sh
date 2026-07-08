#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/ImportToPhotos.app"
APP_BINARY="$APP_DIR/Contents/MacOS/ImportToPhotos"
APP_INFO_PLIST="$ROOT_DIR/Resources/App/Info.plist"
TEMPLATE_DIR="$ROOT_DIR/Resources/ReleasePackage"
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
ZIP_PATH="$ROOT_DIR/dist/$PACKAGE_NAME.zip"
if [[ -e "$PACKAGE_DIR" || -e "$ZIP_PATH" ]]; then
  PACKAGE_NAME="ImportToPhotos-v$VERSION-$ARCH_LABEL-$TIMESTAMP"
  PACKAGE_DIR="$ROOT_DIR/dist/$PACKAGE_NAME"
  ZIP_PATH="$ROOT_DIR/dist/$PACKAGE_NAME.zip"
fi

mkdir -p \
  "$PACKAGE_DIR/Payload/Applications" \
  "$PACKAGE_DIR/Payload/Resources/ServiceWorkflow" \
  "$PACKAGE_DIR/Payload/Resources/LaunchAgent"

ditto "$APP_DIR" "$PACKAGE_DIR/Payload/Applications/ImportToPhotos.app"
rm -f "$PACKAGE_DIR/Payload/Applications/ImportToPhotos.app/Contents/Resources/DefaultImportFolder.txt"
ditto "$SERVICE_SOURCE_DIR" "$PACKAGE_DIR/Payload/Resources/ServiceWorkflow/同步进相册.workflow"
ditto "$LAUNCH_AGENT_SOURCE" "$PACKAGE_DIR/Payload/Resources/LaunchAgent/local.import-to-photos.agent.plist"
ditto "$TEMPLATE_DIR/Install.command" "$PACKAGE_DIR/Install.command"
ditto "$TEMPLATE_DIR/Doctor.command" "$PACKAGE_DIR/Doctor.command"
ditto "$TEMPLATE_DIR/Uninstall.command" "$PACKAGE_DIR/Uninstall.command"
ditto "$TEMPLATE_DIR/README-先双击我.md" "$PACKAGE_DIR/README-先双击我.md"

chmod +x "$PACKAGE_DIR/Install.command" "$PACKAGE_DIR/Doctor.command" "$PACKAGE_DIR/Uninstall.command"

APP_BINARY_TYPE="$(file "$APP_BINARY" | head -n 1 | sed 's/^[^:]*: //')"

{
  echo "PACKAGE_NAME=$PACKAGE_NAME"
  echo "VERSION=$VERSION"
  echo "CREATED_AT=$TIMESTAMP"
  echo "DISTRIBUTION=github-release"
  echo "CPU_ARCH=$CPU_ARCH"
  echo "APP_ARCHS=$APP_ARCHS"
  echo "APP_BINARY_TYPE=$APP_BINARY_TYPE"
  echo "SIGNING=adhoc"
  echo "NOTARIZED=no"
} > "$PACKAGE_DIR/package-info.txt"

ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$ZIP_PATH"

echo "PACKAGE_DIR=$PACKAGE_DIR"
echo "ZIP_PATH=$ZIP_PATH"
