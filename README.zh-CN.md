# Dual

[English](./README.md) | [简体中文](./README.zh-CN.md)

Dual 是一款 macOS 多开应用，用于将应用 bundle 克隆成一个新的独立副本，并赋予新的名称、Bundle ID 和应用身份。它适合需要创建第二个应用实例的人，例如测试、隔离账号或多开场景。

![](./assets/demo.jpg)

| 应用            | 图标                                                                        | 结果 |
| --------------- | --------------------------------------------------------------------------- | ---- |
| Wechat          | ![wechat](https://r2.oimi.space/9z4deF/wechat-32x32.webp)                   | ✅   |
| QQ              | ![qq](https://r2.oimi.space/9z4deF/qq-32x32.webp)                           | ✅   |
| WechatBussiness | ![WechatBussiness](https://r2.oimi.space/9z4deF/wechatBussiness-32x32.webp) | ✅   |
| Ghostty         | ![Ghostty](https://r2.oimi.space/9z4deF/ghostty-32x32.webp)                 | ✅   |
| Kaku            | ![Kaku](https://r2.oimi.space/9z4deF/kaku-32x32.webp)                       | ✅   |
| IINA            | ![IINA](https://r2.oimi.space/9z4deF/iina-32x32.webp)                       | ✅   |
| Telegram        | ![Telegram](https://r2.oimi.space/9z4deF/telegram-32x32.webp)               | ✅   |
| Discord         | ![Discord](https://r2.oimi.space/9z4deF/discord-32x32.webp)                 | ✅   |

## 项目做什么

- 将选中的 `.app` bundle 克隆到新的目标位置。
- 重写克隆应用的 `Info.plist`，设置新的显示名和 Bundle ID。
- 在源应用使用 helper bundle 时，对相关 helper 进行重命名，保证副本仍然可以正常启动。
- 清理旧的 quarantine 数据，并对结果重新签名。
- 可选地在创建副本前清理旧的克隆数据。
- 在目标目录需要权限时，可通过管理员权限完成复制。
- 提供实时日志面板、执行状态和完成后的 Finder 定位按钮。

## 核心功能

- 支持将任意 `.app` 直接拖拽到窗口中。
- 会从 `/Applications` 和 `~/Applications` 中快速推荐常见应用。
- 可自定义副本名称和 Bundle ID。
- 支持选择目标目录，并处理目录可写性。
- UI 同时提供英文和简体中文。
- 具有 macOS 风格的界面、实时进度和成功状态展示。

## 工作方式

应用界面使用 SwiftUI 实现，底层由 `AppCloner` 流程负责实际克隆。该流程会复制源应用、更新身份元数据、在必要时应用具体应用所需的兼容性修复，并重新签名，从而让副本可以正常启动。

## 构建与发布

仓库包含 GitHub Actions 工作流，会为 Intel 和 Apple Silicon 构建 macOS 的 `zip` 和 `dmg` 产物，并在打 tag 或手动触发时发布到 GitHub Releases。

## 使用 Homebrew 安装

你可以通过 `helson-lin/tap` 这个 Homebrew tap 安装 Dual：

```bash
brew tap helson-lin/tap
brew install --cask helson-lin/tap/dual
```

如果你之前手动删过 `Dual.app`，或者本地 cask 记录和实际文件状态不一致，建议先清理旧记录再重新安装：

```bash
brew uninstall --cask --force helson-lin/tap/dual
brew install --cask helson-lin/tap/dual
```

## 测试版安装说明

当前 GitHub Releases 提供的是未正式签名、也未 notarize 的测试包。因此 macOS Gatekeeper 在首次打开时，可能会提示 `"Dual" is damaged and can’t be opened`，或者直接阻止启动。这是当前测试分发方式下的预期表现，不一定代表文件真的损坏。

建议测试用户按下面的顺序安装：

1. 通过 Homebrew 安装：

```bash
brew tap helson-lin/tap
brew install --cask helson-lin/tap/dual
```

2. 或者手动下载最新 release，并将 `Dual.app` 移动到 `/Applications`。
3. 移除 quarantine 标记：

```bash
xattr -cr /Applications/Dual.app
```

4. 如果系统仍然阻止启动，再做一次本地 ad-hoc 重签名：

```bash
codesign --force --deep --sign - /Applications/Dual.app
```

5. 如果还需要确认首次打开，请在 Finder 中对应用执行右键 `打开`。

限制说明：

- 这只是测试版分发的临时绕过方案。
- 在没有 Apple Developer 正式签名和 notarization 的前提下，不同 macOS 版本上的打开体验无法保证完全一致。
- 如果你的应用不在 `/Applications`，请把命令里的路径替换成实际安装路径。

## 项目结构

- `Dual/` - macOS 应用源代码
- `scripts/` - 构建和本地维护脚本
- `.github/workflows/` - GitHub Actions 打包工作流
