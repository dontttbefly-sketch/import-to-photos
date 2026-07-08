#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$SCRIPT_DIR/ImportToPhotos/dist/ImportToPhotos.app"

if [[ ! -x "$APP/Contents/MacOS/ImportToPhotos" ]]; then
  echo "ImportToPhotos.app was not built yet. Building it now..."
  "$SCRIPT_DIR/ImportToPhotos/Scripts/build.sh"
fi

open "$APP" --args "$SCRIPT_DIR"
