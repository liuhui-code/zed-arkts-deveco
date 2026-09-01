# Third-party notices

This project builds on the following MIT-licensed projects:

- [`liuyanghejerry/zed-arkts`](https://github.com/liuyanghejerry/zed-arkts), the original Zed ArkTS extension.
- [`liuyanghejerry/tree-sitter-arkts`](https://github.com/liuyanghejerry/tree-sitter-arkts), the ArkTS grammar.
- [`ohosvscode/arkTS`](https://github.com/ohosvscode/arkTS), which publishes `@arkts/language-server`.

The release workflow downloads the precompiled ArkTS grammar from Zed's official `arkts` 0.3.0 extension archive and verifies its SHA-256 before packaging it. The language server itself is not redistributed in the installer; Zed downloads the pinned npm package on first use.
