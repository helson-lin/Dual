#!/bin/zsh
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-Dual.xcodeproj}"
SCHEME="${SCHEME:-Dual}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCH="${ARCH:?ARCH is required, e.g. x86_64 or arm64}"
ARTIFACT_LABEL="${ARTIFACT_LABEL:-$ARCH}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-15.0}"
BUILD_ROOT="${BUILD_ROOT:-$PWD/.build}"
BACKGROUND_SOURCE="${BACKGROUND_SOURCE:-$PWD/background.png}"
DMG_WINDOW_WIDTH="${DMG_WINDOW_WIDTH:-660}"
DMG_WINDOW_HEIGHT="${DMG_WINDOW_HEIGHT:-400}"

ARCHIVE_PATH="$BUILD_ROOT/archives/${SCHEME}-${ARTIFACT_LABEL}.xcarchive"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData-${ARTIFACT_LABEL}"
EXPORT_DIR="$BUILD_ROOT/export/${ARTIFACT_LABEL}"
DMG_STAGING_DIR="$BUILD_ROOT/dmg/${ARTIFACT_LABEL}"
DMG_TEMP_DIR="$BUILD_ROOT/dmg-temp/${ARTIFACT_LABEL}"
DMG_RW_PATH="$DMG_TEMP_DIR/${SCHEME}-${ARTIFACT_LABEL}-rw.dmg"

rm -rf "$ARCHIVE_PATH" "$DERIVED_DATA_PATH" "$EXPORT_DIR" "$DMG_STAGING_DIR" "$DMG_TEMP_DIR"
mkdir -p "$EXPORT_DIR"
mkdir -p "$DMG_TEMP_DIR"

echo "==> Building $SCHEME ($ARCH / $ARTIFACT_LABEL)"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  ARCHS="$ARCH" \
  MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  ONLY_ACTIVE_ARCH=NO \
  clean archive

APP_PATH="$ARCHIVE_PATH/Products/Applications/${SCHEME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: built app not found at $APP_PATH"
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
MINIMUM_SYSTEM_VERSION=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || true)
EXECUTABLE_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$APP_PATH/Contents/Info.plist")
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
ZIP_NAME="${SCHEME}-${VERSION}-${BUILD_NUMBER}-macos-${ARTIFACT_LABEL}.zip"
ZIP_PATH="$EXPORT_DIR/$ZIP_NAME"
DMG_NAME="${SCHEME}-${VERSION}-${BUILD_NUMBER}-macos-${ARTIFACT_LABEL}.dmg"
DMG_PATH="$EXPORT_DIR/$DMG_NAME"

if [[ "$MINIMUM_SYSTEM_VERSION" != "$DEPLOYMENT_TARGET" ]]; then
  echo "error: expected LSMinimumSystemVersion $DEPLOYMENT_TARGET, got ${MINIMUM_SYSTEM_VERSION:-<missing>}"
  exit 1
fi

if ! /usr/bin/lipo -archs "$EXECUTABLE_PATH" | tr ' ' '\n' | grep -qx "$ARCH"; then
  echo "error: built executable does not contain expected architecture $ARCH"
  /usr/bin/lipo -archs "$EXECUTABLE_PATH"
  exit 1
fi

echo "==> Verified minimum macOS $MINIMUM_SYSTEM_VERSION and architecture $ARCH"

echo "==> Packaging $ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Packaging $DMG_NAME"
mkdir -p "$DMG_STAGING_DIR"
ditto "$APP_PATH" "$DMG_STAGING_DIR/${SCHEME}.app"
ln -s /Applications "$DMG_STAGING_DIR/Applications"
mkdir -p "$DMG_STAGING_DIR/.background"

if [[ ! -f "$BACKGROUND_SOURCE" ]]; then
  echo "error: DMG background image not found: $BACKGROUND_SOURCE"
  exit 1
fi

sips -z "$DMG_WINDOW_HEIGHT" "$DMG_WINDOW_WIDTH" "$BACKGROUND_SOURCE" --out "$DMG_STAGING_DIR/.background/background.png" >/dev/null

create_plain_dmg() {
  echo "note: using plain DMG packaging"
  hdiutil create \
    -srcfolder "$DMG_STAGING_DIR" \
    -volname "$SCHEME" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null
}

create_styled_dmg() {
  hdiutil create \
    -srcfolder "$DMG_STAGING_DIR" \
    -volname "$SCHEME" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$DMG_RW_PATH" >/dev/null

  MOUNT_DIR="$DMG_TEMP_DIR/mount"
  mkdir -p "$MOUNT_DIR"

  ATTACH_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$MOUNT_DIR" "$DMG_RW_PATH")
  DEVICE=$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ {print $1; exit}')
  WINDOW_RIGHT=$((100 + DMG_WINDOW_WIDTH))
  WINDOW_BOTTOM=$((100 + DMG_WINDOW_HEIGHT))

  cleanup_dmg() {
    if [[ -n "${DEVICE:-}" ]]; then
      hdiutil detach "$DEVICE" -quiet || true
    fi
  }

  trap cleanup_dmg EXIT

  /usr/bin/SetFile -a V "$MOUNT_DIR/.background"

  osascript <<EOF
set bgAlias to POSIX file "$MOUNT_DIR/.background/background.png" as alias
tell application "Finder"
  tell disk "$SCHEME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {100, 100, $WINDOW_RIGHT, $WINDOW_BOTTOM}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 80
    set text size of theViewOptions to 14
    set background picture of theViewOptions to bgAlias
    set position of item "$SCHEME.app" of container window to {190, 180}
    set position of item "Applications" of container window to {495, 180}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF

  sync
  hdiutil detach "$DEVICE" -quiet
  trap - EXIT

  hdiutil convert "$DMG_RW_PATH" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH" >/dev/null
}

if [[ -n "${CI:-}" ]]; then
  create_plain_dmg
else
  if ! create_styled_dmg; then
    echo "warning: styled DMG packaging failed, falling back to plain DMG" >&2
    rm -f "$DMG_PATH" "$DMG_RW_PATH"
    rm -rf "$DMG_TEMP_DIR/mount"
    trap - EXIT
    create_plain_dmg
  fi
fi

shasum -a 256 "$ZIP_PATH" | tee "$ZIP_PATH.sha256"
shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "artifact_path=$ZIP_PATH" >> "$GITHUB_OUTPUT"
  echo "dmg_path=$DMG_PATH" >> "$GITHUB_OUTPUT"
  echo "artifact_sha256_path=$ZIP_PATH.sha256" >> "$GITHUB_OUTPUT"
  echo "dmg_sha256_path=$DMG_PATH.sha256" >> "$GITHUB_OUTPUT"
  echo "artifact_name=$ZIP_NAME" >> "$GITHUB_OUTPUT"
  echo "dmg_name=$DMG_NAME" >> "$GITHUB_OUTPUT"
  echo "version=$VERSION" >> "$GITHUB_OUTPUT"
  echo "build_number=$BUILD_NUMBER" >> "$GITHUB_OUTPUT"
fi
