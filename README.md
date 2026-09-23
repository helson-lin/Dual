# Dual

[English](./README.md) | [简体中文](./README.zh-CN.md)

Dual is a macOS app for cloning application bundles into a separate copy with a new name, bundle identifier, and app identity. It is designed for users who need a second copy of an app for testing, isolated sessions, or multi-account workflows.

![](./assets/demo.jpg)

| App             | Logo                                                                        | Work |
| --------------- | --------------------------------------------------------------------------- | ---- |
| Wechat          | ![wechat](https://r2.oimi.space/9z4deF/wechat-32x32.webp)                   | ✅   |
| QQ              | ![qq](https://r2.oimi.space/9z4deF/qq-32x32.webp)                           | ✅   |
| WechatBussiness | ![WechatBussiness](https://r2.oimi.space/9z4deF/wechatBussiness-32x32.webp) | ✅   |
| Ghostty         | ![Ghostty](https://r2.oimi.space/9z4deF/ghostty-32x32.webp)                 | ✅   |
| Kaku            | ![Kaku](https://r2.oimi.space/9z4deF/kaku-32x32.webp)                       | ✅   |
| IINA            | ![IINA](https://r2.oimi.space/9z4deF/iina-32x32.webp)                       | ✅   |
| Telegram        | ![Telegram](https://r2.oimi.space/9z4deF/telegram-32x32.webp)               | ✅   |
| Discord         | ![Discord](https://r2.oimi.space/9z4deF/discord-32x32.webp)                 | ✅   |


## What It Does

- Clones a selected `.app` bundle into a new destination.
- Rewrites the cloned app’s `Info.plist` with a new display name and bundle identifier.
- Renames helper apps when the source app uses helper bundles, so the copied bundle stays launchable.
- Removes stale quarantine data and re-signs the result.
- Optionally clears previous clone data before creating a new copy.
- Supports administrator privileges when the target location requires elevated access.
- Shows a live log panel and final status, including a Finder reveal action after success.

## Key Features

- Drag and drop any `.app` bundle into the window.
- Quick-pick common apps from `/Applications` and `~/Applications`.
- Custom clone name and bundle identifier fields.
- Destination folder selection with writable-path handling.
- Localized UI strings in English and Simplified Chinese.
- Polished macOS-style UI with live progress and success states.

## How It Works

The app uses SwiftUI for the interface and an `AppCloner` pipeline behind the scenes. That pipeline copies the source app, updates identity metadata, applies app-specific compatibility fixes when needed, and re-signs the bundle so the clone can launch normally.

## Build and Release

The GitHub Actions workflow signs and notarizes Intel and Apple Silicon `zip` and `dmg` artifacts before publishing them to GitHub Releases. Configure its Apple credentials interactively with:

```bash
scripts/configure-signing-secrets.sh
```

Configure Sparkle's EdDSA update keys the same way:

```bash
scripts/configure-update-secrets.sh
```

## Install with Homebrew

You can install Dual from the `helson-lin/tap` Homebrew tap:

```bash
brew tap helson-lin/tap
brew install --cask helson-lin/tap/dual
```

If you are upgrading from a broken or manually removed app bundle, clear the old cask record first:

```bash
brew uninstall --cask --force helson-lin/tap/dual
brew install --cask helson-lin/tap/dual
```

## Distribution

GitHub Release and Homebrew artifacts are signed with Developer ID, notarized by Apple, and validated by Gatekeeper before publication. The release workflow fails instead of publishing when signing or notarization cannot be completed.

## Project Structure

- `Dual/` - the macOS app source
- `scripts/` - build and local maintenance scripts
- `.github/workflows/` - GitHub Actions packaging workflow

## License

Dual is licensed under GNU GPLv3 with additional Commons Clause terms. Personal, non-commercial use only unless the copyright holder grants explicit written permission. Derivative works must retain the same license terms. See [LICENSE](./LICENSE) for the complete terms.
