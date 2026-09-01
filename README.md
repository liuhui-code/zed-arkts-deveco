# ArkTS DevEco for Zed

面向 HarmonyOS / OpenHarmony 项目的 Zed ArkTS 开发扩展。它为 `.ets` 文件提供语法高亮和语言服务器能力，并自动发现常见位置中的 DevEco Studio SDK。

> Windows Release 中的 EXE 是 **ArkTS 扩展安装器**，不是 Zed 编辑器本体。请先从 [Zed 官网](https://zed.dev/download) 安装 Zed。

## 功能

- `.ets` 文件识别与 Tree-sitter 语法高亮
- 自动补全、悬停信息、文档符号和工作区符号
- 跳转到定义、查找引用和转到实现
- 重命名、签名帮助、内联提示和语义令牌
- 自动安装固定版本的 `@arkts/language-server@1.3.10`
- 自动发现 macOS 和 Windows 常见 DevEco SDK 安装路径
- 使用兼容代理处理 SDK 初始化参数和语言服务器退出流程

在一个真实 HarmonyOS 工程的协议验证中，语言服务器返回了 113 个补全项、1 个定义目标、10 处引用、2 个重命名编辑和 255 个工作区符号。实际结果会随项目和 SDK 版本变化。

## Windows 快速安装

### 1. 安装 Zed

从 [Zed 下载页](https://zed.dev/download)安装，或者在 PowerShell 中执行：

```powershell
winget install -e --id ZedIndustries.Zed
```

Zed 官方的 Windows 版本要求和故障排查见 [Zed on Windows](https://zed.dev/docs/windows)。

### 2. 安装本扩展

1. 关闭 Zed。
2. 从本仓库的 [Releases](https://github.com/liuhui-code/zed-arkts-deveco/releases) 下载 `zed-arkts-deveco-<版本>-windows-x64.exe`。
3. 运行安装器，然后重新启动 Zed。
4. 打开 DevEco 工程根目录，再打开任意 `.ets` 文件。
5. 首次使用时，Zed 会自动下载固定版本的 ArkTS language server。

安装器按当前用户安装，无需管理员权限，也不会覆盖 `settings.json`。扩展安装到：

```text
%LOCALAPPDATA%\Zed\extensions\installed\arkts-deveco
```

可以在 Windows 的“设置 → 应用 → 已安装的应用”中卸载 `ArkTS DevEco for Zed`。

首个版本未进行 Authenticode 代码签名，因此 SmartScreen 可能显示“未知发布者”。安装器由公开的 GitHub Actions 工作流构建；Release 同时提供 `SHA256SUMS.txt`。

## 配置过程

标准安装位置通常不需要手工配置。兼容代理按以下顺序寻找 SDK：

- 环境变量 `DEVECO_SDK_HOME`
- macOS：`/Applications/DevEco-Studio.app/Contents/sdk/default`
- Windows：`%ProgramFiles%\Huawei\DevEco Studio\sdk\default`
- Windows 当前用户：`%LOCALAPPDATA%\Programs\Huawei\DevEco Studio\sdk\default`

### 推荐的 Zed 配置

在 Zed 中按 `Ctrl+Alt+,`（macOS 为 `Cmd+Alt+,`）打开 `settings.json`，合并 [configs/settings.example.jsonc](configs/settings.example.jsonc) 中的配置。

Windows 用户配置文件位置：

```text
%APPDATA%\Zed\settings.json
```

macOS / Linux 用户配置文件位置：

```text
~/.config/zed/settings.json
```

如果 SDK 不在标准目录，可以在初始化参数中显式设置：

```json5
{
  "lsp": {
    "arkts-language-server": {
      "initialization_options": {
        "debug": false,
        "ets": {
          "sdkPath": "D:\\Huawei\\Sdk\\openharmony",
          "hmsPath": "D:\\Huawei\\Sdk\\hms"
        }
      }
    }
  }
}
```

也可以把 [configs/project-settings.example.json](configs/project-settings.example.json) 复制为项目根目录下的 `.zed/settings.json`，让配置只作用于当前工程。

### 打开真实 DevEco 工程

建议打开包含 `build-profile.json5`、`oh-package.json5` 和 `entry/` 的工程根目录，而不是只打开单个 `.ets` 文件。这样语言服务器才能建立完整的项目索引。

如果同时安装了其他接管 `.ets` 文件的 ArkTS 扩展，请先禁用另一个扩展，避免语言识别和 LSP 冲突。

## 验证补全、跳转和查询

打开工程中的 `.ets` 文件后，确认 Zed 状态栏语言显示为 `ArkTS DevEco`，然后依次测试：

| 功能 | Windows / Linux | macOS |
|---|---|---|
| 自动补全 | `Ctrl+Space` | `Ctrl+Space` |
| 跳转到定义 | `F12` | `F12`，部分键盘需要 `Fn+F12` |
| 查找全部引用 | `Alt+Shift+F12` | `Option+Shift+F12` |
| 重命名 | `F2` | `F2`，部分键盘需要 `Fn+F2` |
| 悬停信息 | `Ctrl+K`，再按 `Ctrl+I` | `Cmd+K`，再按 `Cmd+I` |
| 命令面板 | `Ctrl+Shift+P` | `Cmd+Shift+P` |

完整的可搜索、可打印快捷键文档见 [docs/zed-shortcuts.html](docs/zed-shortcuts.html)。

如果没有出现补全或跳转：

1. 在命令面板运行 `zed: open log`。
2. 搜索 `arkts-language-server`、`npm` 或 `sdkPath`。
3. 确认 Node 下载未被代理或防火墙阻断。
4. 确认 SDK 路径包含 `openharmony`，并重新打开项目。
5. 检查是否有另一个 ArkTS 扩展同时接管 `.ets`。

## macOS / Linux 安装

在扩展进入 Zed 官方扩展市场之前，可使用开发扩展方式：

1. 克隆本仓库。
2. 在 Zed 命令面板运行 `zed: install dev extension`。
3. 选择克隆后的仓库目录。

开发扩展的构建依赖 Rust、`wasm32-wasip2` target 和 WASI SDK；Zed 可以自动处理其中大部分依赖。参见 [Zed 开发扩展文档](https://zed.dev/docs/extensions/developing-extensions)。

## 从源码构建

构建 WebAssembly 扩展：

```sh
rustup target add wasm32-wasip2
cargo build --release --target wasm32-wasip2
```

在 macOS / Linux 生成可移植扩展包：

```sh
./scripts/package-extension.sh 0.1.0
```

在 Windows 安装 Rust 与 [NSIS](https://nsis.sourceforge.io/) 后生成 EXE：

```powershell
./scripts/package-windows.ps1 -Version 0.1.0
```

推送 `v*` 标签会触发公开的 GitHub Actions Release 工作流，构建、静默安装/卸载冒烟测试并发布 EXE、扩展压缩包和 SHA-256 校验文件。

## 官方 Zed 文档

- [安装 Zed](https://zed.dev/docs/installation)
- [Windows 支持](https://zed.dev/docs/windows)
- [配置 Zed](https://zed.dev/docs/configuring-zed)
- [全部设置项](https://zed.dev/docs/reference/all-settings)
- [安装扩展](https://zed.dev/docs/extensions/installing-extensions)
- [开发扩展](https://zed.dev/docs/extensions/developing-extensions)
- [语言扩展](https://zed.dev/docs/extensions/languages)
- [快捷键](https://zed.dev/docs/key-bindings)
- [任务](https://zed.dev/docs/tasks)
- [Zed 源代码](https://github.com/zed-industries/zed)

## 项目边界

本项目提供编辑、索引和导航能力。HarmonyOS 应用的编译、签名、模拟器、真机运行和发布仍由 DevEco Studio、Hvigor 与 HarmonyOS SDK 完成。

## 来源与许可证

本项目基于 [`liuyanghejerry/zed-arkts`](https://github.com/liuyanghejerry/zed-arkts) 增强。语法解析器和 language server 的来源及打包方式见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

本仓库使用 MIT License，见 [LICENSE](LICENSE)。Zed 是独立项目，本仓库与 Zed Industries 或 Huawei 不存在官方隶属关系。
