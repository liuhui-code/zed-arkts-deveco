# ArkTS DevEco for Zed

ArkTS syntax highlighting and language intelligence for real DevEco Studio projects in [Zed](https://zed.dev/). The extension runs on macOS, Windows and Linux; GitHub Releases include a one-click Windows x64 installer.

基于 Zed 的 ArkTS / DevEco Studio 开发环境，支持 macOS、Windows 和 Linux。GitHub Release 提供 Windows x64 安装 EXE。

## Features

- `.ets` file detection and Tree-sitter syntax highlighting
- Completion, hover and document/workspace symbols
- Go to definition, references and implementations
- Rename, signature help, inlay hints and semantic tokens
- Automatic installation of the pinned `@arkts/language-server@1.3.10`
- Automatic DevEco SDK discovery on standard macOS and Windows installations
- Clean language-server shutdown through a small compatibility proxy

The implementation was exercised against a real HarmonyOS project: 113 completion entries, one definition target, 10 references, two rename edits and 255 workspace symbols were returned in the protocol smoke test.

## Install

### Windows x64

1. Close Zed.
2. Download `zed-arkts-deveco-<version>-windows-x64.exe` from [Releases](https://github.com/liuhui-code/zed-arkts-deveco/releases).
3. Run the installer and restart Zed.
4. Open a DevEco project and then an `.ets` file. Zed downloads the language server on first use.

The installer is per-user, requires no administrator privileges and does not modify `settings.json`. It installs the extension under `%LOCALAPPDATA%\Zed\extensions\installed\arkts-deveco` and includes a normal Windows uninstaller.

The initial release is not Authenticode-signed, so Windows SmartScreen may show an unknown-publisher warning. Release assets are built publicly by GitHub Actions and include GitHub's published SHA-256 digest.

### macOS / Linux

Until this fork is accepted into the Zed extension registry:

1. Clone this repository.
2. In Zed, run `zed: install dev extension`.
3. Select the cloned directory.

Rust, the `wasm32-wasip2` target and a WASI SDK are required only when installing as a development extension. Zed downloads the language server itself.

Do not enable another ArkTS extension at the same time; two extensions claiming `.ets` files can conflict.

## DevEco SDK discovery

The compatibility proxy checks these standard locations:

- macOS: `/Applications/DevEco-Studio.app/Contents/sdk/default`
- Windows: `%ProgramFiles%\Huawei\DevEco Studio\sdk\default`
- Windows per-user install: `%LOCALAPPDATA%\Programs\Huawei\DevEco Studio\sdk\default`
- Custom install: environment variable `DEVECO_SDK_HOME`

You can override discovery in Zed's `settings.json`:

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

On Windows, Zed's user settings file is `%APPDATA%\Zed\settings.json`.

## Build

Build the WebAssembly extension:

```sh
rustup target add wasm32-wasip2
cargo build --release --target wasm32-wasip2
```

Create the installable extension archive on macOS/Linux:

```sh
./scripts/package-extension.sh 0.1.0
```

Create the Windows EXE on Windows with Rust and NSIS installed:

```powershell
./scripts/package-windows.ps1 -Version 0.1.0
```

Tags matching `v*` run the public release workflow, which builds both the Windows installer and the portable extension archive.

## Scope

This project supplies editing intelligence. Building, signing, running and deploying HarmonyOS applications still use DevEco Studio, Hvigor and the HarmonyOS toolchain.

## Credits and license

This is an enhanced fork of [`liuyanghejerry/zed-arkts`](https://github.com/liuyanghejerry/zed-arkts). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for grammar and language-server credits.

MIT licensed. See [LICENSE](LICENSE).
