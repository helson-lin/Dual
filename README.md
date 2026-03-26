# Dual

[English](./README.md) | [简体中文](./README.zh-CN.md)

This repository contains the macOS app project and its release packaging workflow.

## GitHub Actions Release Flow

The repository includes a GitHub Actions workflow at `.github/workflows/build-macos.yml`.

### Triggers

- Manual run: start the `Build macOS` workflow from GitHub Actions.
- Tag release: push a tag such as `v1.0.0`.

### Optional Manual Release Publishing

When starting the workflow manually, you can also publish the build outputs to GitHub Releases:

- Set `release_tag` to a tag name such as `v1.0.0`.
- The workflow will create or update that GitHub Release and upload the generated assets.

### Generated Artifacts

Each run builds both macOS architectures and produces:

- `Dual-<version>-<build>-macos-intel.zip`
- `Dual-<version>-<build>-macos-intel.dmg`
- `Dual-<version>-<build>-macos-apple-silicon.zip`
- `Dual-<version>-<build>-macos-apple-silicon.dmg`
- matching `.sha256` checksum files

### Implementation Notes

- `macos-15-intel` builds the `x86_64` package.
- `macos-15` builds the `arm64` package.
- Each architecture exports both `.zip` and `.dmg`.
- The `.dmg` uses `background.png` from the repository root as its background image.
- Pushing a `v*` tag uploads the build outputs to GitHub Releases automatically.
- A manual workflow run only publishes to GitHub Releases when `release_tag` is provided.

## Local Release Packaging

You can reuse the same packaging script locally:

```bash
ARCH=x86_64 ARTIFACT_LABEL=intel ./scripts/build-release.sh
ARCH=arm64 ARTIFACT_LABEL=apple-silicon ./scripts/build-release.sh
```

Build outputs are written under `.build/`.

## Local Testing Utilities

### Re-sign a Local App Bundle

```bash
chmod +x /Users/lin/person/Dual/scripts/re-sign-local.sh
/Users/lin/person/Dual/scripts/re-sign-local.sh
```

This script performs ad-hoc re-signing and prints `codesign` and `spctl` validation results.

### Remove the Quarantine Attribute

```bash
chmod +x /Users/lin/person/Dual/scripts/remove-quarantine.sh
/Users/lin/person/Dual/scripts/remove-quarantine.sh
```

This only removes the quarantine flag. It does not replace code signing or notarization.

## Manual App Clone Notes

If you are cloning an Electron app bundle manually, the usual steps are:

1. Copy the app bundle:

   ```bash
   ditto --norsrc --noqtn /Applications/Notion.app /Applications/Notion2.app
   ```

2. Update the main `Info.plist`:
   - change `CFBundleIdentifier`
   - change `CFBundleName`
   - change `CFBundleDisplayName`
   - remove `ElectronAsarIntegrity`

3. Rename every helper bundle:
   - rename the bundle directory
   - rename the executable
   - update `CFBundleExecutable` and `CFBundleIdentifier` in each helper `Info.plist`
   - follow the main app name plus the standard helper suffix

4. Patch the Electron Framework fuse if required:
   - sentinel: `dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX`
   - offset: `sentinel + 32 + 2 + 4`
   - change `'1'` to `'0'`

5. Clear quarantine:

   ```bash
   xattr -cr /Applications/Notion2.app
   ```

6. Re-sign the copied app:

   ```bash
   codesign --force --deep --sign - /Applications/Notion2.app
   ```

## Important Notes

- If you are not injecting additional frameworks, you usually do not need `--options runtime` or custom entitlements.
- Helper bundles must be renamed correctly, or Electron may fail to launch and exit with `SIGTRAP`.
- The fuse patch and `ElectronAsarIntegrity` removal are only needed for some Electron versions.

## Simpler Alternative

If your goal is just to run another instance of the app, a separate user data directory is usually more stable than copying the bundle:

```bash
open -n /Applications/Notion.app --args --user-data-dir=~/Notion2
```

Another option is to use a Chrome or Edge PWA instead of duplicating the macOS app bundle.
