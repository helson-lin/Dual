# Dual

[English](./README.md) | [简体中文](./README.zh-CN.md)

把任意 macOS 应用克隆成一个拥有独立名称、Bundle ID 和身份的副本。

[![License](https://img.shields.io/badge/license-GPLv3%20%2B%20Commons%20Clause-blue)](./LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/helson-lin/Dual)](https://github.com/helson-lin/Dual/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/helson-lin/Dual/total)](https://github.com/helson-lin/Dual/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2012.0%2B-lightgrey)](https://github.com/helson-lin/Dual)

Dual 会把选中的 `.app` 复制到新的目标位置，重写其显示名和 Bundle ID，并重新签名，让副本可以独立启动和运行，与原应用互不干扰——适合用于测试、隔离会话，或在同一台 Mac 上并行使用同一应用的多个账号。

![Dual](./assets/demo.png)

## 功能特性

- 将选中的 `.app` 克隆到新位置，并赋予独立的显示名和 Bundle ID。
- 支持将任意 `.app` 直接拖拽进窗口，也可以从 `/Applications` 和 `~/Applications` 中快速挑选常见应用。
- 对使用 helper bundle 的应用重命名 helper，保证副本仍可正常启动。
- 克隆过程中应用针对特定应用的兼容性修复，并为 Electron 副本在每次启动时指定独立用户数据目录（包括 Finder 双击启动）。
- 可选为副本添加徽标图标，便于与原应用区分。
- 创建新副本前清理旧的克隆数据，必要时执行更深层的隔离清理。
- 清除失效的 quarantine 属性，并重新签名克隆出的 bundle。
- 当目标位置需要更高权限时，可请求管理员权限完成克隆。
- 记录已有的克隆并显示其来源与是否为最新版本，提供实时日志面板，克隆成功后可在 Finder 中定位。
- 界面同时提供英文和简体中文本地化。

## 环境要求

- macOS 12.0（Monterey）或更高版本。
- 同时支持 Apple Silicon 和 Intel 芯片的 Mac。

## 安装

### Homebrew

通过 `helson-lin/tap` 这个 Homebrew tap 安装 Dual：

```bash
brew tap helson-lin/tap
brew install --cask helson-lin/tap/dual
```

### 直接下载

前往 [GitHub Releases](https://github.com/helson-lin/Dual/releases/latest) 下载适合当前 Mac 的最新 `.dmg`，打开后将 Dual 拖入“应用程序”文件夹。

![像素风 DMG 安装界面](./background.png)

## 使用方法

1. 将 `.app` 拖入拖放区域，或从 `/Applications`、`~/Applications` 推荐列表中快速选择一个应用。
2. 在克隆面板中设置副本的显示名和 Bundle ID（Dual 会根据源应用自动给出建议值）。
3. 选择目标目录，或保留默认的 `/Applications/Cloned`。
4. 按需开启徽标图标和“克隆前清理旧数据”，然后开始克隆。
5. 克隆完成后，点击定位按钮即可在 Finder 中打开新副本。

## 兼容性

以下应用已验证过对应的兼容性修复效果。其他应用也可能可以正常克隆——欢迎提交 issue 或 PR 分享你的测试结果，帮助完善这张表格。

| 应用              | 图标                                                                          | 结果 |
| --------------- | --------------------------------------------------------------------------- | -- |
| WeChat          | ![wechat](https://r2.oimi.space/9z4deF/wechat-32x32.webp)                   | ✅  |
| QQ              | ![qq](https://r2.oimi.space/9z4deF/qq-32x32.webp)                           | ✅  |
| WeChat Business | ![WeChat Business](https://r2.oimi.space/9z4deF/wechatBussiness-32x32.webp) | ✅  |
| Ghostty         | ![Ghostty](https://r2.oimi.space/9z4deF/ghostty-32x32.webp)                 | ✅  |
| Kaku            | ![Kaku](https://r2.oimi.space/9z4deF/kaku-32x32.webp)                       | ✅  |
| IINA            | ![IINA](https://r2.oimi.space/9z4deF/iina-32x32.webp)                       | ✅  |
| Telegram        | ![Telegram](https://r2.oimi.space/9z4deF/telegram-32x32.webp)               | ✅  |
| Discord         | ![Discord](https://r2.oimi.space/9z4deF/discord-32x32.webp)                 | ✅  |

## 工作原理

界面使用 SwiftUI 实现，实际克隆逻辑由 `AppCloner` 流程完成：

1. 读取源应用的 Bundle ID，识别是否匹配某个特定应用的兼容性配置（例如 Telegram、Discord）。
2. 若新 Bundle ID 与源应用相同，则拒绝该请求。
3. 如果启用了徽标图标，先生成对应的图标文件。
4. 在复制前清理旧的克隆数据（必要时执行更深层的按应用隔离清理）。
5. 使用 `ditto` 复制应用 bundle，若目标已存在则先删除。
6. 重写 `Info.plist`，写入新的显示名和 Bundle ID，并安装徽标图标。
7. 按需应用特定应用的补丁（Telegram 身份标签、Discord 用户数据路径）。
8. 重命名 Electron helper 和主程序；为 Electron 副本安装传入独立 `--user-data-dir` 的启动器，再重新签名。
9. 清除扩展属性，并使用 `codesign` 重新签名克隆出的 bundle。

## 开发

本地构建需要安装 Xcode，并支持 macOS 12.0 或更高版本的 SDK。

```bash
open Dual.xcodeproj
```

如需按 CI 相同的方式产出签名、公证并打包好的构建产物，使用 `scripts/build-release.sh`（通过 `ARCH` 指定 `arm64` 或 `x86_64`）：

```bash
ARCH=arm64 scripts/build-release.sh
```

`scripts/` 目录下的其他脚本：

| 脚本                             | 作用                                           |
| ------------------------------ | -------------------------------------------- |
| `build-release.sh`             | 构建、签名、公证并打包发布用的 `zip`/`dmg`。                 |
| `configure-signing-secrets.sh` | 交互式地将 Apple 签名/公证凭据上传到 GitHub。               |
| `configure-update-secrets.sh`  | 交互式地生成并上传 Sparkle EdDSA 更新密钥。                |
| `re-sign-local.sh`             | 为本地开发测试临时重新签名一份 `.app` 副本。                   |
| `remove-quarantine.sh`         | 移除 `.app` 上的 `com.apple.quarantine` 扩展属性。    |
| `sync-homebrew-tap.sh`         | 将更新后的 cask 发布到 `helson-lin/homebrew-tap` 仓库。 |

## 构建与分发

`Build macOS` GitHub Actions 工作流（`.github/workflows/build-macos.yml`）会分别构建 Intel 和 Apple Silicon 版本，使用 Developer ID 证书签名，并通过 `scripts/build-release.sh` 调用 `notarytool` 完成公证。在打 tag 推送（或手动指定 release tag 触发）时，它还会：

- 为每个架构生成经 Sparkle EdDSA 签名的 appcast，使应用可以在应用内检查并安装更新。
- 将签名后的 `zip`/`dmg` 产物和 appcast 发布到 GitHub Release。
- 使用新版本号、构建号和校验和同步更新 `helson-lin/homebrew-tap` 中的 cask（`scripts/sync-homebrew-tap.sh`）。

在工作流可以产出签名发布版本之前，需先运行 `scripts/configure-signing-secrets.sh` 配置 Apple 签名/公证凭据，并运行 `scripts/configure-update-secrets.sh` 配置 Sparkle 更新密钥。

## 项目结构

```text
Dual/
├── Dual/                      # SwiftUI 应用源码（界面、AppCloner 流程、本地化）
├── Dual.xcodeproj/            # Xcode 工程配置
├── scripts/                   # 构建、签名与维护脚本
├── .github/workflows/         # GitHub Actions 构建与发布工作流
├── assets/                    # README 使用的截图
├── background.png             # DMG 安装界面背景图
└── LICENSE                    # GPLv3 + Commons Clause 许可证文本
```

## 故障排查

**Homebrew cask 记录损坏或过期。** 如果之前手动删除过应用，或 cask 记录与实际安装状态不一致，先强制卸载再重新安装：

```bash
brew uninstall --cask --force helson-lin/tap/dual
brew install --cask helson-lin/tap/dual
```

**首次启动被 Gatekeeper 拦截。** 发布版本均已签名并公证，出现该问题通常是复制方式导致残留了 quarantine 标记。可使用 `scripts/remove-quarantine.sh`（默认作用于 `/Applications/Dual.app`）清除，该脚本只移除 `com.apple.quarantine` 属性，不会替代签名或公证：

```bash
scripts/remove-quarantine.sh /Applications/Dual.app
```

如果仍被拦截，可在 Finder 中右键点击应用选择“打开”，或在系统设置 → 隐私与安全性中手动允许。

## 参与贡献

欢迎提交 issue 和 PR。[兼容性](#兼容性) 表格由社区共同维护——如果你成功克隆了表中未列出的应用，欢迎分享你的测试结果。

## 许可证

Dual 采用 GNU GPLv3，并附加 Commons Clause 条款。除非版权所有者明确书面许可，否则仅限个人、非商业使用；衍生作品必须保留相同许可证条款。完整条款见 [LICENSE](./LICENSE)。
