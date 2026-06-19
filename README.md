# cliplet

cliplet 是一个轻量级 macOS 剪切板历史应用。它常驻菜单栏，监听系统剪切板里的文本和图片，并通过可配置的全局快捷键打开一个类似 Windows 剪切板历史的紧凑面板。

## 功能

- 菜单栏应用，不显示 Dock 图标
- 全局快捷键，默认 `⌃⌥V`
- 支持文本和图片剪切板历史
- 重复内容会移动到历史顶部
- 可配置历史保存数量，范围为 1 到 200 条
- 点击、双击或按回车键可把历史项重新复制回剪切板
- 使用 `UserDefaults` 在本地持久化历史记录和设置
- 使用 GitHub Actions 做 CI，并通过版本标签自动打包发布

## 环境要求

- macOS 13 或更高版本
- Swift 5.9 或更高版本

## 开发

```sh
make build
make test
make run
```

## 本地打包

```sh
make package
open dist/cliplet.app
```

本地打包产物会使用 ad-hoc 签名，但不会经过 Apple 公证。在新机器上首次打开时，macOS 可能需要从 Finder 的右键菜单中打开一次。

## 发布

推送语义化版本标签后，会自动创建发布版本：

```sh
./scripts/create_release_tag.sh v0.2.0
```

GitHub Actions 发布流程会构建 `cliplet.app`，进行 ad-hoc 签名，压缩为 zip，并上传到 GitHub 发布版本。

## 当前范围

cliplet 会保存文本和图片剪切板条目。选择历史项后会把它复制回系统剪切板；它不会自动粘贴到当前前台应用，因此不需要辅助功能权限。
