#!/bin/zsh
set -euo pipefail

PROJECT_PATH="${PROJECT_PATH:-Dual.xcodeproj}"
SCHEME="${SCHEME:-Dual}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCH="${ARCH:?ARCH is required, e.g. x86_64 or arm64}"
ARTIFACT_LABEL="${ARTIFACT_LABEL:-$ARCH}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-13.0}"
BUILD_ROOT="${BUILD_ROOT:-$PWD/.build}"
BACKGROUND_SOURCE="${BACKGROUND_SOURCE:-$PWD/background.png}"
DMG_WINDOW_WIDTH="${DMG_WINDOW_WIDTH:-660}"
DMG_WINDOW_HEIGHT="${DMG_WINDOW_HEIGHT:-480}"
RELEASE_TAG="${RELEASE_TAG:-}"
VERSION_OVERRIDE="${VERSION_OVERRIDE:-}"
BUILD_NUMBER_OVERRIDE="${BUILD_NUMBER_OVERRIDE:-}"
DMGBUILD_PYTHONPATH="${DMGBUILD_PYTHONPATH:-}"
FORCE_DMGBUILD="${FORCE_DMGBUILD:-}"

if [[ -z "$RELEASE_TAG" && "${GITHUB_REF_TYPE:-}" == "tag" && -n "${GITHUB_REF_NAME:-}" ]]; then
  RELEASE_TAG="$GITHUB_REF_NAME"
fi

normalize_version_from_tag() {
  local tag="$1"
  tag="${tag#v}"
  tag="${tag%%+*}"
  if [[ "$tag" =~ ^([0-9]+(\.[0-9]+){0,2})(-[0-9A-Za-z.-]+)?$ ]]; then
    printf '%s\n' "${match[1]}"
    return 0
  fi
  return 1
}

if [[ -z "$VERSION_OVERRIDE" && -n "$RELEASE_TAG" ]]; then
  if VERSION_OVERRIDE=$(normalize_version_from_tag "$RELEASE_TAG"); then
    echo "==> Using marketing version $VERSION_OVERRIDE from release tag $RELEASE_TAG"
  else
    echo "warning: release tag $RELEASE_TAG does not contain a valid numeric app version; using project MARKETING_VERSION" >&2
    VERSION_OVERRIDE=""
  fi
fi

if [[ -z "$BUILD_NUMBER_OVERRIDE" && -n "$RELEASE_TAG" && -n "${GITHUB_RUN_NUMBER:-}" ]]; then
  BUILD_NUMBER_OVERRIDE="$GITHUB_RUN_NUMBER"
  echo "==> Using build number $BUILD_NUMBER_OVERRIDE from GITHUB_RUN_NUMBER"
fi

ARCHIVE_PATH="$BUILD_ROOT/archives/${SCHEME}-${ARTIFACT_LABEL}.xcarchive"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData-${ARTIFACT_LABEL}"
EXPORT_DIR="$BUILD_ROOT/export/${ARTIFACT_LABEL}"
DMG_STAGING_DIR="$BUILD_ROOT/dmg/${ARTIFACT_LABEL}"
DMG_TEMP_DIR="$BUILD_ROOT/dmg-temp/${ARTIFACT_LABEL}"
DMG_RW_PATH="$DMG_TEMP_DIR/${SCHEME}-${ARTIFACT_LABEL}-rw.dmg"
DMG_STAGING_BACKGROUND="$DMG_STAGING_DIR/.background/background.png"
DMGBUILD_BACKGROUND="$DMG_TEMP_DIR/dmgbuild-background.tiff"

rm -rf "$ARCHIVE_PATH" "$DERIVED_DATA_PATH" "$EXPORT_DIR" "$DMG_STAGING_DIR" "$DMG_TEMP_DIR"
mkdir -p "$EXPORT_DIR"
mkdir -p "$DMG_TEMP_DIR"

XCODEBUILD_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -destination "generic/platform=macOS"
  -archivePath "$ARCHIVE_PATH"
  -derivedDataPath "$DERIVED_DATA_PATH"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_IDENTITY=""
  ARCHS="$ARCH"
  MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
  ONLY_ACTIVE_ARCH=NO
)

if [[ -n "$VERSION_OVERRIDE" ]]; then
  XCODEBUILD_ARGS+=(MARKETING_VERSION="$VERSION_OVERRIDE")
fi

if [[ -n "$BUILD_NUMBER_OVERRIDE" ]]; then
  XCODEBUILD_ARGS+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER_OVERRIDE")
fi

echo "==> Building $SCHEME ($ARCH / $ARTIFACT_LABEL)"
xcodebuild "${XCODEBUILD_ARGS[@]}" clean archive

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
ARTIFACT_VERSION_LABEL="$VERSION"
if [[ -n "$RELEASE_TAG" ]]; then
  ARTIFACT_VERSION_LABEL="${RELEASE_TAG#v}"
fi
ZIP_NAME="${SCHEME}-${ARTIFACT_VERSION_LABEL}-${BUILD_NUMBER}-macos-${ARTIFACT_LABEL}.zip"
ZIP_PATH="$EXPORT_DIR/$ZIP_NAME"
DMG_NAME="${SCHEME}-${ARTIFACT_VERSION_LABEL}-${BUILD_NUMBER}-macos-${ARTIFACT_LABEL}.dmg"
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

sips -s format png -z "$DMG_WINDOW_HEIGHT" "$DMG_WINDOW_WIDTH" "$BACKGROUND_SOURCE" --out "$DMG_STAGING_BACKGROUND" >/dev/null
sips -s format tiff -z "$DMG_WINDOW_HEIGHT" "$DMG_WINDOW_WIDTH" "$BACKGROUND_SOURCE" --out "$DMGBUILD_BACKGROUND" >/dev/null

create_plain_dmg() {
  echo "note: using plain DMG packaging"
  hdiutil create \
    -srcfolder "$DMG_STAGING_DIR" \
    -volname "$SCHEME" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null
}

has_dmgbuild() {
  if [[ -n "$DMGBUILD_PYTHONPATH" ]]; then
    PYTHONPATH="$DMGBUILD_PYTHONPATH" python3 -c "import dmgbuild" >/dev/null 2>&1
  else
    python3 -c "import dmgbuild" >/dev/null 2>&1
  fi
}

has_dmg_style_python() {
  if [[ -n "$DMGBUILD_PYTHONPATH" ]]; then
    PYTHONPATH="$DMGBUILD_PYTHONPATH" python3 -c "import ds_store, mac_alias" >/dev/null 2>&1
  else
    python3 -c "import ds_store, mac_alias" >/dev/null 2>&1
  fi
}

create_dmg_with_dmgbuild() {
  local settings_path="$DMG_TEMP_DIR/dmgbuild-settings.json"

  cat >"$settings_path" <<EOF
{
  "title": "$SCHEME",
  "background": "$DMGBUILD_BACKGROUND",
  "icon-size": 80,
  "window": {
    "position": { "x": 100, "y": 100 },
    "size": { "width": $DMG_WINDOW_WIDTH, "height": $DMG_WINDOW_HEIGHT }
  },
  "format": "UDZO",
  "filesystem": "HFS+",
  "contents": [
    {
      "path": "$APP_PATH",
      "name": "$SCHEME.app",
      "type": "file",
      "x": 190,
      "y": 180
    },
    {
      "path": "/Applications",
      "name": "Applications",
      "type": "link",
      "x": 495,
      "y": 180
    }
  ]
}
EOF

  if [[ -n "$DMGBUILD_PYTHONPATH" ]]; then
    PYTHONPATH="$DMGBUILD_PYTHONPATH" python3 -m dmgbuild "$SCHEME" "$DMG_PATH" -s "$settings_path" --no-hidpi
  else
    python3 -m dmgbuild "$SCHEME" "$DMG_PATH" -s "$settings_path" --no-hidpi
  fi
}

create_dmg_without_finder() {
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

  cleanup_dmg() {
    if [[ -n "${DEVICE:-}" ]]; then
      hdiutil detach "$DEVICE" -quiet || true
    fi
  }

  trap cleanup_dmg EXIT

  if [[ -x /usr/bin/SetFile ]]; then
    /usr/bin/SetFile -a V "$MOUNT_DIR/.background" || true
  fi

  PYTHONPATH="$DMGBUILD_PYTHONPATH" python3 - "$MOUNT_DIR" "$DMG_WINDOW_WIDTH" "$DMG_WINDOW_HEIGHT" <<'PY'
from pathlib import Path
import sys

from ds_store import DSStore
from mac_alias import Alias

mount_dir = Path(sys.argv[1])
window_width = int(sys.argv[2])
window_height = int(sys.argv[3])
background = mount_dir / ".background" / "background.png"
background_alias = Alias.for_file(str(background))

icon_view_options = {
    "arrangeBy": "none",
    "backgroundColorBlue": 1.0,
    "backgroundColorGreen": 1.0,
    "backgroundColorRed": 1.0,
    "backgroundImageAlias": background_alias.to_bytes(),
    "backgroundType": 2,
    "gridOffsetX": 0.0,
    "gridOffsetY": 0.0,
    "gridSpacing": 100.0,
    "iconSize": 80.0,
    "labelOnBottom": True,
    "showIconPreview": False,
    "showItemInfo": False,
    "textSize": 14.0,
    "viewOptionsVersion": 1,
}

browser_window_state = {
    "ContainerShowSidebar": False,
    "ShowPathbar": False,
    "ShowSidebar": False,
    "ShowStatusBar": False,
    "ShowTabView": False,
    "ShowToolbar": False,
    "WindowBounds": f"{{{{100, 100}}, {{{window_width}, {window_height}}}}}",
}

with DSStore.open(str(mount_dir / ".DS_Store"), "w+") as store:
    store["."]["bwsp"] = browser_window_state
    store["."]["icvp"] = icon_view_options
    store["."]["pBB0"] = ("blob", background_alias.to_bytes())
    store["Dual.app"]["Iloc"] = (190, 180)
    store["Applications"]["Iloc"] = (495, 180)
    store.flush()
PY

  sync
  hdiutil detach "$DEVICE" -quiet
  DEVICE=""
  trap - EXIT

  hdiutil convert "$DMG_RW_PATH" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH" >/dev/null
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
  DS_STORE_PATH="$MOUNT_DIR/.DS_Store"

  cleanup_dmg() {
    if [[ -n "${DEVICE:-}" ]]; then
      hdiutil detach "$DEVICE" -quiet || true
    fi
  }

  trap cleanup_dmg EXIT

  /usr/bin/SetFile -a V "$MOUNT_DIR/.background"

  osascript <<EOF
set dmgFolder to POSIX file "$MOUNT_DIR" as alias
set bgAlias to POSIX file "$MOUNT_DIR/.background/background.png" as alias
tell application "Finder"
  activate
  open dmgFolder
  delay 1
  set dmgWindow to front window
  set current view of dmgWindow to icon view
  set toolbar visible of dmgWindow to false
  set statusbar visible of dmgWindow to false
  set the bounds of dmgWindow to {100, 100, $WINDOW_RIGHT, $WINDOW_BOTTOM}
  set theViewOptions to the icon view options of dmgWindow
  set arrangement of theViewOptions to not arranged
  set icon size of theViewOptions to 80
  set text size of theViewOptions to 14
  set background picture of theViewOptions to bgAlias
  set position of item "$SCHEME.app" of dmgFolder to {190, 180}
  set position of item "Applications" of dmgFolder to {495, 180}
  update dmgFolder without registering applications
  delay 5
  close dmgWindow
end tell
EOF

  for _ in {1..10}; do
    if [[ -f "$DS_STORE_PATH" ]]; then
      break
    fi
    sleep 1
  done

  if [[ ! -f "$DS_STORE_PATH" ]]; then
    echo "error: Finder did not persist DMG window metadata (.DS_Store missing)" >&2
    return 1
  fi

  for _ in {1..10}; do
    if ! hdiutil info | grep -q "$MOUNT_DIR"; then
      DEVICE=""
      break
    fi
    sleep 1
  done

  if [[ -n "${DEVICE:-}" ]]; then
    sync
    sleep 1
    hdiutil detach "$DEVICE" -quiet
  fi
  trap - EXIT

  hdiutil convert "$DMG_RW_PATH" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH" >/dev/null
}

if [[ -n "${CI:-}" ]]; then
  if has_dmg_style_python; then
    create_dmg_without_finder
  else
    echo "error: ds_store and mac_alias are required for styled CI DMG packaging" >&2
    echo "Install dmgbuild before running this script, or set DMGBUILD_PYTHONPATH to a directory containing ds_store and mac_alias." >&2
    exit 1
  fi
elif [[ -n "$FORCE_DMGBUILD" ]]; then
  if has_dmgbuild; then
    create_dmg_with_dmgbuild
  else
    create_plain_dmg
  fi
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
