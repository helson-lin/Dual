#!/usr/bin/env bash
set -euo pipefail

command -v gh >/dev/null || { echo "error: GitHub CLI (gh) is required" >&2; exit 1; }
gh auth status >/dev/null

DEFAULT_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
read -r -p "GitHub repository [${DEFAULT_REPO}]: " REPO
REPO=${REPO:-$DEFAULT_REPO}
[[ -n "$REPO" ]] || { echo "error: repository is required" >&2; exit 1; }

printf 'Resolving Sparkle tools…\n'
xcodebuild -resolvePackageDependencies -project Dual.xcodeproj -scheme Dual -derivedDataPath .build/DerivedData-sparkle-keys >/dev/null
GENERATE_KEYS=$(find .build/DerivedData-sparkle-keys/SourcePackages/artifacts -type f -name generate_keys -perm -111 -print -quit)
[[ -n "$GENERATE_KEYS" ]] || { echo "error: Sparkle generate_keys was not found" >&2; exit 1; }

printf '\nSparkle will create or show the update signing key in your login Keychain.\n'
"$GENERATE_KEYS"
read -r -p "Paste the public EdDSA key printed above: " PUBLIC_KEY
[[ -n "$PUBLIC_KEY" ]] || { echo "error: public key is required" >&2; exit 1; }

PRIVATE_KEY=$(mktemp)
rm -f "$PRIVATE_KEY"
trap 'rm -f "$PRIVATE_KEY"' EXIT
"$GENERATE_KEYS" -x "$PRIVATE_KEY" >/dev/null
[[ -s "$PRIVATE_KEY" ]] || { echo "error: Sparkle private key export failed" >&2; exit 1; }

printf '\nThe following GitHub Actions secrets will be replaced in %s:\n' "$REPO"
printf '  SPARKLE_PUBLIC_ED_KEY\n  SPARKLE_PRIVATE_ED_KEY\n'
read -r -p "Continue? [y/N]: " CONFIRM
[[ "$CONFIRM" == [yY] ]] || { echo "Cancelled."; exit 0; }

printf '%s' "$PUBLIC_KEY" | gh secret set SPARKLE_PUBLIC_ED_KEY --repo "$REPO"
gh secret set SPARKLE_PRIVATE_ED_KEY --repo "$REPO" < "$PRIVATE_KEY"
echo "Sparkle update secrets configured for $REPO."
