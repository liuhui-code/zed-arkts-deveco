# Third-party notices / 第三方说明

This project builds on the following projects:

- [`liuyanghejerry/zed-arkts`](https://github.com/liuyanghejerry/zed-arkts), the original Zed ArkTS extension.
- [`liuyanghejerry/tree-sitter-arkts`](https://github.com/liuyanghejerry/tree-sitter-arkts), the ArkTS grammar. Its `package.json` declares the MIT license.
- [`ohosvscode/arkTS`](https://github.com/ohosvscode/arkTS), which publishes `@arkts/language-server`.
- [`openharmony-sig/deveco-cli`](https://gitcode.com/openharmony-sig/deveco-cli), the official external CLI invoked by the bundled build tasks when installed by the user.

The release workflow downloads the precompiled ArkTS grammar from Zed's official `arkts` 0.3.0 extension archive and verifies its SHA-256 before packaging it. Version 0.4.1 uses the separately installed DevEco CLI official ArkTS LSP by default. If DevEco CLI is absent, it bundles a diagnostic `@arkts/language-server` entry module built from the public [`zed-arkts-deveco-v0.3.4`](https://github.com/liuhui-code/arkTS/tree/zed-arkts-deveco-v0.3.4) source tag; Zed downloads the pinned 1.3.10 npm package to provide fallback runtime dependencies. DevEco CLI is not redistributed.

本仓库的 Release 工作流从 Zed 官方扩展服务下载 `arkts` 0.3.0 中的预编译 grammar，并在打包前校验固定 SHA-256。0.4.1 默认调用用户另行安装的 DevEco CLI 官方 ArkTS LSP；只有未找到 DevEco CLI 时，才使用由公开 [`zed-arkts-deveco-v0.3.4`](https://github.com/liuhui-code/arkTS/tree/zed-arkts-deveco-v0.3.4) 源码标签构建的诊断入口及固定的 1.3.10 npm 运行依赖。安装器不重新分发 DevEco CLI。
