#!/bin/zsh
set -euo pipefail

APP_PATH="/Applications/Dual.app"

if [[ ! -d "$APP_PATH" || "${APP_PATH:e}" != "app" ]]; then
  echo "error: app not found: $APP_PATH"
  exit 1
fi

echo "==> Re-signing: $APP_PATH"

codesign --remove-signature "$APP_PATH" 2>/dev/null || true
codesign --force --deep --sign - "$APP_PATH"

echo
echo "==> Verification"
codesign --verify --deep --strict "$APP_PATH" || true
spctl --assess --type execute --verbose=4 "$APP_PATH" || true

echo
echo "Done."
echo "If Gatekeeper still blocks first launch, use Finder -> right click -> Open,"
echo "or allow it in System Settings -> Privacy & Security."
