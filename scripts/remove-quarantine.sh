#!/bin/zsh
set -euo pipefail

APP_PATH="/Applications/Dual.app"

if [[ ! -d "$APP_PATH" || "${APP_PATH:e}" != "app" ]]; then
  echo "error: app not found: $APP_PATH"
  exit 1
fi

echo "==> Removing quarantine attribute: $APP_PATH"
xattr -dr com.apple.quarantine "$APP_PATH"

echo
echo "Done."
echo "This only removes the quarantine flag. It does not replace signing or notarization."
