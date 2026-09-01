# Third-party notices / 第三方说明

This project builds on the following projects:

- [`liuyanghejerry/zed-arkts`](https://github.com/liuyanghejerry/zed-arkts), the original Zed ArkTS extension.
- [`liuyanghejerry/tree-sitter-arkts`](https://github.com/liuyanghejerry/tree-sitter-arkts), the ArkTS grammar. Its `package.json` declares the MIT license.
- [`ohosvscode/arkTS`](https://github.com/ohosvscode/arkTS), which publishes `@arkts/language-server`.
- [`openharmony-sig/deveco-cli`](https://gitcode.com/openharmony-sig/deveco-cli), the official external CLI invoked by the bundled build tasks when installed by the user.

The release workflow downloads the precompiled ArkTS grammar from Zed's official `arkts` 0.3.0 extension archive and verifies its SHA-256 before packaging it. The language server and DevEco CLI are not redistributed in the installer. Zed downloads the pinned language-server npm package on first use; users install DevEco CLI separately to enable build tasks.

本仓库的 Release 工作流从 Zed 官方扩展服务下载 `arkts` 0.3.0 中的预编译 grammar，并在打包前校验固定 SHA-256。安装器不重新分发 language server 或 DevEco CLI；Zed 会在首次使用时下载固定版本的 language-server npm 包，构建任务则调用用户另行安装的 DevEco CLI。
