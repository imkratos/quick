# quick

quick 是一款原生 macOS 应用切换工具，使用 Swift、SwiftUI 和 AppKit 构建，搭配系统 Liquid Glass 材质。按住激活键，再按应用对应的字符，即可打开或切换应用，减少在窗口和 Dock 之间寻找目标的操作。

## 功能

- **三种应用列表**：Dock 模式跟随 Dock 中的应用，可将访达置顶；切换器模式显示正在运行的应用，并支持排除指定应用；自定义模式支持添加、移除、拖动排序和指定快捷键。
- **键盘快速切换**：默认使用 `⌥ Option`，也可选择 Command、Control 或 Shift。支持数字、字母及左右手键盘区域；按住激活键时可连续切换应用。
- **多套自定义配置**：保存、载入和删除应用列表，支持 JSON 导入导出，也可从 Dock 或运行中的应用载入列表。
- **外观设置**：实时预览 Liquid Glass 效果，调整背景透明度、大小和屏幕位置，并可在光标所在屏幕显示。
- **切换行为设置**：调整显示延迟和自动隐藏时间，支持双击激活键暂停或启用，以及再次选择前台应用时隐藏该应用。
- **静默名单**：在指定应用中隐藏切换浮层，并可同时停用切换快捷键。
- **菜单栏与登录启动**：通过菜单栏访问应用；登录启动由 macOS 管理，需系统接受注册。
- **本地使用统计**：记录总切换次数及各应用的切换次数。

## 系统要求与安装

- Apple Silicon Mac（arm64）。
- macOS 27 或更新版本；当前发布包的最低系统版本为 27.0。

在本仓库的 **Releases** 页面下载 `quick-X.Y.Z-macos-arm64.dmg`，打开后将 `quick.app` 拖入 `Applications`，再从“应用程序”启动。

当前构建采用临时签名（ad-hoc），未配置 Apple Developer ID 签名或 Apple 公证。首次打开时可能受到 Gatekeeper 限制；确认来源可信后，可在“系统设置 → 隐私与安全性”中按系统提示允许打开。

发布页同时提供 `.sha256` 文件，将其与 DMG 放在同一目录后可校验下载内容：

```bash
shasum -a 256 -c quick-0.0.2-macos-arm64.dmg.sha256
```

## 快速上手

1. 启动 quick，在“配置”中选择 Dock、切换器或自定义模式。
2. 按住 `⌥ Option`，等待浮层出现，再按目标应用下方的字符切换应用。
3. 在“系统设置 → 隐私与安全性 → 辅助功能”中授权 quick，以启用完整的全局按键拦截、无需等待浮层的快捷直达及窗口焦点恢复。权限状态会自动更新。
4. 按需要设置外观、激活键、静默名单及自定义配置。

未授权辅助功能时，仍可长按激活键显示浮层，再使用系统快捷键选择应用。显示延迟设为 `2.5` 表示不自动显示浮层；自动隐藏设为 `0` 表示不自动隐藏。

## 本地构建

推荐使用 Xcode 27.2，包含 macOS SDK 和 Swift 工具链。Swift Package 清单要求 Swift tools 6.2 或更新版本，无第三方包依赖。

在项目根目录执行：

```bash
bash build.sh
open quick.app
```

生成带版本号的 DMG：

```bash
bash scripts/package-dmg.sh 0.0.2
```

产物位于 `dist/`，包含 arm64 DMG 和 SHA-256 校验文件。DMG 内包含应用及指向“应用程序”的快捷方式，应用包版本号取自传入的版本。

## GitHub Actions 自动发布

工作流位于 [`.github/workflows/release.yml`](.github/workflows/release.yml)。将本目录作为 GitHub 仓库根目录上传后，推送 `vX.Y.Z` 格式的标签即可自动发布，例如：

```bash
git tag v0.0.2
git push origin v0.0.2
```

请先提交并推送代码及工作流，再创建标签。仅在本地创建标签不会触发 Actions；`v0.0.2-beta` 等预发布标签目前不支持。

工作流使用 GitHub 的 [`xcode-27` Apple Silicon runner](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)，选择 Xcode 27.2，依次完成：

1. 校验标签格式，运行现有机制回归检查。
2. 构建 Release 应用，将标签版本写入应用包并重新临时签名。
3. 创建、验证 DMG，生成 SHA-256 校验文件。
4. 保存 Actions 构建产物，创建 GitHub Release 并上传安装包与校验文件。

无需额外配置 Secrets，发布使用 GitHub 自动提供的 `GITHUB_TOKEN`。仓库需启用 Actions，并允许工作流使用 `contents: write` 权限。该 runner 当前属于预览环境，后续可用性以 GitHub 文档为准。相同标签重新运行时会覆盖对应 Release 附件。

## 开发与验证

运行不需要界面交互的机制检查：

```bash
swiftc Sources/Mechanics.swift checks/mechanics-check.swift -o /tmp/quick-mechanics-check
/tmp/quick-mechanics-check
```

在本地桌面会话中执行键盘回归：

```bash
python3 checks/run-keyboard-e2e.py fallback tap packaged
```

该检查会打开两个临时输入窗口，验证连续切换、重复按键、松键顺序与普通输入恢复；完整全局拦截测试需要辅助功能权限。正式应用测试会临时使用独立配置，结束后恢复原配置，因此不在发布 CI 中运行。

`python3 main.py` 是 Craft Anything 的启动适配入口，只负责构建与启动 Swift 程序。`python3 main.py --screenshot shots/now.png` 可在约 120 帧后保存截图并退出，不主动激活窗口。
