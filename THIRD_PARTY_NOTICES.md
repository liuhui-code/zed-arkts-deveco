# Third-party notices / 第三方说明

This project builds on the following projects:

- [`liuyanghejerry/zed-arkts`](https://github.com/liuyanghejerry/zed-arkts), the original Zed ArkTS extension.
- [`liuyanghejerry/tree-sitter-arkts`](https://github.com/liuyanghejerry/tree-sitter-arkts), the ArkTS grammar. Its `package.json` declares the MIT license.
- [`ohosvscode/arkTS`](https://github.com/ohosvscode/arkTS), which publishes `@arkts/language-server`.
- [`openharmony-sig/deveco-cli`](https://gitcode.com/openharmony-sig/deveco-cli), the official external CLI invoked by the bundled build tasks when installed by the user.

The release workflow downloads the precompiled ArkTS grammar from Zed's official `arkts` 0.3.0 extension archive and verifies its SHA-256 before packaging it. Version 0.3.3 bundles a diagnostic `@arkts/language-server` entry module built from the public [`zed-arkts-deveco-v0.3.3`](https://github.com/liuhui-code/arkTS/tree/zed-arkts-deveco-v0.3.3) source tag; Zed downloads the pinned 1.3.10 npm package on first use to provide its runtime dependencies, then the extension installs the diagnostic entry module. DevEco CLI is not redistributed; users install it separately to enable build tasks.

本仓库的 Release 工作流从 Zed 官方扩展服务下载 `arkts` 0.3.0 中的预编译 grammar，并在打包前校验固定 SHA-256。0.3.3 会携带由公开 [`zed-arkts-deveco-v0.3.3`](https://github.com/liuhui-code/arkTS/tree/zed-arkts-deveco-v0.3.3) 源码标签构建的诊断 Language Server 入口；Zed 首次使用时下载固定的 1.3.10 npm 包以提供运行依赖，随后扩展安装诊断入口。安装器不重新分发 DevEco CLI，构建任务仍调用用户另行安装的 DevEco CLI。
