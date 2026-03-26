# Dual

[English](./README.md) | [简体中文](./README.zh-CN.md)

本仓库包含 macOS 应用工程及其发布打包流程。

## GitHub Actions 发布流程

仓库内已包含 GitHub Actions 工作流 `.github/workflows/build-macos.yml`。

### 触发方式

- 手动触发：在 GitHub Actions 中运行 `Build macOS`。
- Tag 发布：推送形如 `v1.0.0` 的 tag。

### 手动触发时可选发布到 GitHub Release

手动运行工作流时，也可以把构建产物发布到 GitHub Releases：

- 将 `release_tag` 设置为类似 `v1.0.0` 的 tag 名称。
- 工作流会创建或更新对应的 GitHub Release，并上传生成的产物。

### 生成产物

每次运行都会构建两个 macOS 架构，并产出：

- `Dual-<version>-<build>-macos-intel.zip`
- `Dual-<version>-<build>-macos-intel.dmg`
- `Dual-<version>-<build>-macos-apple-silicon.zip`
- `Dual-<version>-<build>-macos-apple-silicon.dmg`
- 对应的 `.sha256` 校验文件

### 实现说明

- `macos-15-intel` 用于构建 `x86_64` 包。
- `macos-15` 用于构建 `arm64` 包。
- 每个架构都会同时导出 `.zip` 和 `.dmg`。
- `.dmg` 使用仓库根目录的 `background.png` 作为背景图。
- 推送 `v*` tag 时，会自动将构建产物上传到 GitHub Releases。
- 手动运行工作流时，只有传入 `release_tag` 才会发布到 GitHub Releases。

## 本地打包 Release

你也可以在本地直接复用同一套打包脚本：

```bash
ARCH=x86_64 ARTIFACT_LABEL=intel ./scripts/build-release.sh
ARCH=arm64 ARTIFACT_LABEL=apple-silicon ./scripts/build-release.sh
```

构建输出会写入 `.build/` 目录。

## 本地测试工具

### 重新签名本地 App Bundle

```bash
chmod +x /Users/lin/person/Dual/scripts/re-sign-local.sh
/Users/lin/person/Dual/scripts/re-sign-local.sh
```

该脚本会执行 ad-hoc 重签名，并输出 `codesign` 和 `spctl` 校验结果。

### 移除 Quarantine 属性

```bash
chmod +x /Users/lin/person/Dual/scripts/remove-quarantine.sh
/Users/lin/person/Dual/scripts/remove-quarantine.sh
```

该脚本仅移除 quarantine 标记，不能替代签名或 notarization。

## 手动克隆 App 的说明

如果你是在手动复制一个 Electron app bundle，通常步骤如下：

1. 复制 app bundle：

   ```bash
   ditto --norsrc --noqtn /Applications/Notion.app /Applications/Notion2.app
   ```

2. 修改主 `Info.plist`：
   - 修改 `CFBundleIdentifier`
   - 修改 `CFBundleName`
   - 修改 `CFBundleDisplayName`
   - 删除 `ElectronAsarIntegrity`

3. 重命名所有 helper bundle：
   - 重命名 bundle 目录
   - 重命名可执行文件
   - 更新每个 helper `Info.plist` 中的 `CFBundleExecutable` 和 `CFBundleIdentifier`
   - 命名遵循主应用名加标准 helper 后缀

4. 如有需要，补丁 Electron Framework fuse：
   - sentinel: `dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX`
   - offset: `sentinel + 32 + 2 + 4`
   - 将 `'1'` 改成 `'0'`

5. 清理 quarantine：

   ```bash
   xattr -cr /Applications/Notion2.app
   ```

6. 重新签名复制后的 app：

   ```bash
   codesign --force --deep --sign - /Applications/Notion2.app
   ```

## 重要说明

- 如果没有注入额外 framework，通常不需要 `--options runtime` 或自定义 entitlements。
- Helper bundle 必须正确重命名，否则 Electron 可能无法启动并直接以 `SIGTRAP` 退出。
- fuse 补丁和移除 `ElectronAsarIntegrity` 只在部分 Electron 版本中需要。

## 更简单的替代方案

如果你的目标只是运行该应用的另一个实例，通常比复制 bundle 更稳妥的方式是使用独立的用户数据目录：

```bash
open -n /Applications/Notion.app --args --user-data-dir=~/Notion2
```

另一种方式是直接使用 Chrome 或 Edge 的 PWA，而不是复制 macOS app bundle。
