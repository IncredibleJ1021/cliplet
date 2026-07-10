# AGENTS.md

## 项目概览

cliplet 是一个轻量级 macOS 菜单栏剪切板历史应用，使用 Swift Package Manager、AppKit 和一个仅依赖 Foundation 的核心模块构建。

## 构建与测试

- 构建：`swift build`
- 测试：`swift test`
- 本地运行：`swift run cliplet`
- 打包 ad-hoc 签名的应用包：`./scripts/package_app.sh`

## 发布

- 版本标签必须使用 `vMAJOR.MINOR.PATCH` 格式，例如 `v0.2.0`。
- 发布前必须在干净的 `main` 分支上确认 `HEAD` 与 `origin/main` 完全一致。默认运行 `./scripts/create_release_tag.sh v0.4.1` 执行本地测试、本地打包、推送 `main` 和版本标签。
- 若机器只有 Command Line Tools、无法运行 XCTest，先推送 `main` 并等待同一提交的 GitHub CI 成功，再使用 `CLIPLET_TEST_GATE=github SWIFT_BUILD_SYSTEM=native ./scripts/create_release_tag.sh v0.4.1`；脚本只接受该精确提交的成功 CI。
- `scripts/package_app.sh` 使用 SwiftPM 构建 macOS 13.0 的 arm64 与 x86_64 两个切片，合并为 universal app，并执行显式的 ad-hoc 签名和包校验。
- 推送版本标签会触发 `.github/workflows/release.yml`，生成 `cliplet.app`，打包为 zip 后上传到 GitHub 发布版本。
- ad-hoc 签名不提供 Apple Developer ID 或 notarization；发布说明不得声称已完成公证。

## 架构说明

- `Sources/ClipletCore` 存放可持久化的模型和剪切板历史逻辑。
- `Sources/Cliplet` 存放 AppKit 界面、剪切板轮询、全局快捷键注册和设置逻辑。
- 剪切板历史行为需要在 `Tests/ClipletCoreTests` 中保持测试覆盖。
- 当前应用保存文本和图片剪切板内容；图片条目以剪切板数据形式持久化，并在历史面板中显示缩略图。

## 编码约定

- 界面代码保持 AppKit 原生，并尽量少引入依赖。
- 除非能明显降低复杂度，否则不要新增第三方包。
- 优先使用小而聚焦的类型，避免把逻辑堆进宽泛的应用级控制器。
- 不要在没有辅助功能权限流程和清晰用户控制项的情况下加入自动粘贴行为。
