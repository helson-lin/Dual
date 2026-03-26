## Electron App Clone (Stable Method)

## GitHub Actions 打包

仓库已添加 GitHub Actions 工作流：

- 手动触发：GitHub Actions 里运行 `Build macOS`
- 发布触发：推送 tag，例如 `v1.0.0`
- 产物：
  - `Dual-<version>-<build>-macos-intel.zip`
  - `Dual-<version>-<build>-macos-intel.dmg`
  - `Dual-<version>-<build>-macos-apple-silicon.zip`
  - `Dual-<version>-<build>-macos-apple-silicon.dmg`
  - 对应的 `.sha256` 校验文件

实现方式：

- `macos-15-intel` runner 打 `x86_64`
- `macos-15` runner 打 `arm64`
- 每个架构同时导出 `.zip` 和 `.dmg`
- `.dmg` 会使用仓库根目录的 `background.png` 作为背景图，并在打包时缩放到 `660x400`
- 打 tag 时会把两个包自动上传到 GitHub Release

本地也可以直接复用同一套脚本：

```bash
ARCH=x86_64 ARTIFACT_LABEL=intel ./scripts/build-release.sh
ARCH=arm64 ARTIFACT_LABEL=apple-silicon ./scripts/build-release.sh
```

## Local Testing Scripts

### 重新签名本地 App

```bash
chmod +x /Users/lin/person/Dual/scripts/re-sign-local.sh
/Users/lin/person/Dual/scripts/re-sign-local.sh
```

### 移除 quarantine 属性

```bash
chmod +x /Users/lin/person/Dual/scripts/remove-quarantine.sh
/Users/lin/person/Dual/scripts/remove-quarantine.sh
```

说明：
- `re-sign-local.sh` 会做 ad-hoc 重签名，并输出 `codesign` / `spctl` 检查结果
- `remove-quarantine.sh` 只移除下载隔离标记，不替代签名或 notarization

### 步骤

1. 复制 App：
   ```bash
   ditto --norsrc --noqtn /Applications/Notion.app /Applications/Notion2.app
   ```

2. 修改主 Info.plist：
   - CFBundleIdentifier → 新的
   - CFBundleName → 新的
   - CFBundleDisplayName → 新的
   - 移除 ElectronAsarIntegrity

3. **重命名所有 Helper**：
   - 目录名、可执行文件、Info.plist 里的 CFBundleExecutable 和 CFBundleIdentifier
   - 规则：主名 + Helper 后缀

4. 补丁 Electron Framework fuse：
   - sentinel: `dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX`
   - offset: sentinel+32+2+4
   - 把 '1' 改成 '0'

5. 清 quarantine：
   ```bash
   xattr -cr /Applications/Notion2.app
   ```

6. 重新签名：
   ```bash
   codesign --force --deep --sign - /Applications/Notion2.app
   ```

---

### 关键说明

- 不注入 Framework 时，不需要 --options runtime 或 entitlements
- Helper 必须重命名，否则 Electron 找不到 Helper 直接 SIGTRAP
- fuse 补丁和 ElectronAsarIntegrity 只对部分 Electron 版本必要

---

### 推荐更稳用法

1. 不复制 app，直接用 user-data-dir 多开：
   ```bash
   open -n /Applications/Notion.app --args --user-data-dir=~/Notion2
   ```
2. 或用 Chrome/Edge PWA
