#!/usr/bin/env bash
set -euo pipefail

command -v gh >/dev/null || { echo "error: GitHub CLI (gh) is required" >&2; exit 1; }
gh auth status >/dev/null

DEFAULT_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
read -r -p "GitHub repository [${DEFAULT_REPO}]: " REPO
REPO=${REPO:-$DEFAULT_REPO}
[[ -n "$REPO" ]] || { echo "error: repository is required" >&2; exit 1; }

read -r -p "Developer ID Application .p12 path: " P12_PATH
[[ -f "$P12_PATH" ]] || { echo "error: file not found: $P12_PATH" >&2; exit 1; }
read -r -s -p "Password for the .p12 file: " P12_PASSWORD
printf '\n'
[[ -n "$P12_PASSWORD" ]] || { echo "error: .p12 password is required" >&2; exit 1; }

printf 'Available Developer ID identities:\n'
IDENTITIES=$(security find-identity -v -p codesigning | grep 'Developer ID Application' || true)
printf '%s\n' "$IDENTITIES"
read -r -p "Choose identity number or enter its SHA-1: " SIGNING_IDENTITY
if [[ "$SIGNING_IDENTITY" =~ ^[0-9]+$ ]]; then
  SIGNING_IDENTITY=$(printf '%s\n' "$IDENTITIES" | awk -v choice="$SIGNING_IDENTITY" '$1 == choice ")" { print $2; exit }')
fi
[[ "$SIGNING_IDENTITY" =~ ^[[:xdigit:]]{40}$ ]] || { echo "error: choose a listed number or enter a 40-character SHA-1 identity" >&2; exit 1; }

read -r -p "App Store Connect AuthKey .p8 path: " API_KEY_PATH
[[ -f "$API_KEY_PATH" ]] || { echo "error: file not found: $API_KEY_PATH" >&2; exit 1; }
read -r -p "App Store Connect API Key ID: " API_KEY_ID
read -r -p "App Store Connect Issuer ID: " API_ISSUER_ID
[[ -n "$API_KEY_ID" && -n "$API_ISSUER_ID" ]] || { echo "error: API Key ID and Issuer ID are required" >&2; exit 1; }

printf '\nThe following GitHub Actions secrets will be replaced in %s:\n' "$REPO"
printf '  APPLE_DEVELOPER_ID_P12_BASE64\n  APPLE_DEVELOPER_ID_P12_PASSWORD\n  APPLE_SIGNING_IDENTITY\n  APPLE_API_KEY_P8_BASE64\n  APPLE_API_KEY_ID\n  APPLE_API_ISSUER_ID\n'
read -r -p "Continue? [y/N]: " CONFIRM
[[ "$CONFIRM" == [yY] ]] || { echo "Cancelled."; exit 0; }

set_secret() {
  printf '%s' "$2" | gh secret set "$1" --repo "$REPO"
}

set_secret APPLE_DEVELOPER_ID_P12_BASE64 "$(base64 < "$P12_PATH" | tr -d '\n')"
set_secret APPLE_DEVELOPER_ID_P12_PASSWORD "$P12_PASSWORD"
set_secret APPLE_SIGNING_IDENTITY "$SIGNING_IDENTITY"
set_secret APPLE_API_KEY_P8_BASE64 "$(base64 < "$API_KEY_PATH" | tr -d '\n')"
set_secret APPLE_API_KEY_ID "$API_KEY_ID"
set_secret APPLE_API_ISSUER_ID "$API_ISSUER_ID"

unset P12_PASSWORD
echo "Signing secrets configured for $REPO."
