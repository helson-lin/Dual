#!/usr/bin/env bash
set -euo pipefail

DIST_DIR="${DIST_DIR:-dist}"
RELEASE_TAG="${RELEASE_TAG:?RELEASE_TAG is required}"
TAP_REPO="${TAP_REPO:-helson-lin/homebrew-tap}"
TAP_BRANCH="${TAP_BRANCH:-main}"
TAP_GIT_TOKEN="${TAP_GIT_TOKEN:?TAP_GIT_TOKEN is required}"
TAP_CLONE_DIR="${TAP_CLONE_DIR:-$PWD/.build/homebrew-tap}"
TAP_CASK_PATH="${TAP_CASK_PATH:-Casks/dual.rb}"

find_single_file() {
  local pattern="$1"
  local result
  result=$(find "$DIST_DIR" -type f -name "$pattern" | head -n 1)
  if [[ -z "$result" ]]; then
    echo "error: expected to find $pattern under $DIST_DIR" >&2
    exit 1
  fi
  printf '%s\n' "$result"
}

extract_version_and_build() {
  local filename="$1"
  local parsed
  parsed=$(printf '%s\n' "$filename" | sed -E 's/^Dual-(.+)-([0-9]+)-macos-(apple-silicon|intel)\.dmg$/\1,\2/')
  if [[ "$parsed" == "$filename" ]]; then
    echo "error: failed to parse version/build from $filename" >&2
    exit 1
  fi
  printf '%s\n' "$parsed"
}

extract_sha256() {
  local path="$1"
  if [[ -f "$path.sha256" ]]; then
    awk '{ print $1 }' "$path.sha256"
  else
    shasum -a 256 "$path" | awk '{ print $1 }'
  fi
}

APPLE_DMG=$(find_single_file 'Dual-*-macos-apple-silicon.dmg')
INTEL_DMG=$(find_single_file 'Dual-*-macos-intel.dmg')

APPLE_INFO=$(extract_version_and_build "$(basename "$APPLE_DMG")")
INTEL_INFO=$(extract_version_and_build "$(basename "$INTEL_DMG")")

if [[ "$APPLE_INFO" != "$INTEL_INFO" ]]; then
  echo "error: apple/intel artifact version mismatch: $APPLE_INFO vs $INTEL_INFO" >&2
  exit 1
fi

VERSION="${APPLE_INFO%%,*}"
BUILD_NUMBER="${APPLE_INFO##*,}"
APPLE_SHA=$(extract_sha256 "$APPLE_DMG")
INTEL_SHA=$(extract_sha256 "$INTEL_DMG")

rm -rf "$TAP_CLONE_DIR"
git clone "https://x-access-token:${TAP_GIT_TOKEN}@github.com/${TAP_REPO}.git" "$TAP_CLONE_DIR"

cat >"$TAP_CLONE_DIR/$TAP_CASK_PATH" <<EOF
cask "dual" do
  arch arm: "apple-silicon", intel: "intel"

  version "${VERSION},${BUILD_NUMBER}"
  sha256 arm:   "${APPLE_SHA}",
         intel: "${INTEL_SHA}"

  url "https://github.com/helson-lin/Dual/releases/download/v#{version.csv.first}/Dual-#{version.csv.first}-#{version.csv.second}-macos-#{arch}.dmg",
      verified: "github.com/helson-lin/Dual/"
  name "Dual"
  desc "Clone macOS app bundles with a new name and bundle identifier"
  homepage "https://github.com/helson-lin/Dual"

  depends_on macos: ">= :monterey"

  app "Dual.app"

  caveats do
    <<~EOS
      Dual is currently distributed as an unsigned, unnotarized test build.

      If macOS blocks the app after installation, remove the quarantine flag:
        xattr -cr /Applications/Dual.app

      If the app still cannot be opened, apply a local ad-hoc signature:
        codesign --force --deep --sign - /Applications/Dual.app
    EOS
  end
end
EOF

git -C "$TAP_CLONE_DIR" config user.name "github-actions[bot]"
git -C "$TAP_CLONE_DIR" config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if git -C "$TAP_CLONE_DIR" diff --quiet -- "$TAP_CASK_PATH"; then
  echo "No Homebrew tap changes detected."
  exit 0
fi

git -C "$TAP_CLONE_DIR" add "$TAP_CASK_PATH"
git -C "$TAP_CLONE_DIR" commit -m "Update Dual cask to ${VERSION} (${BUILD_NUMBER})"
git -C "$TAP_CLONE_DIR" push origin "$TAP_BRANCH"
