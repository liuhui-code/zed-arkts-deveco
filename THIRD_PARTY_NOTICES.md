# Third-party notices / 第三方说明

This project builds on the following projects:

- [`liuyanghejerry/zed-arkts`](https://github.com/liuyanghejerry/zed-arkts), the original Zed ArkTS extension.
- [`liuyanghejerry/tree-sitter-arkts`](https://github.com/liuyanghejerry/tree-sitter-arkts), the ArkTS grammar. Its `package.json` declares the MIT license.
- [`ohosvscode/arkTS`](https://github.com/ohosvscode/arkTS), which publishes `@arkts/language-server`.

The release workflow downloads the precompiled ArkTS grammar from Zed's official `arkts` 0.3.0 extension archive and verifies its SHA-256 before packaging it. The language server itself is not redistributed in the installer; Zed downloads the pinned npm package on first use.

本仓库的 Release 工作流从 Zed 官方扩展服务下载 `arkts` 0.3.0 中的预编译 grammar，并在打包前校验固定 SHA-256。安装器不重新分发 language server；Zed 会在首次使用时下载固定版本的 npm 包。
