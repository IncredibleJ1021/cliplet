# cliplet

cliplet 是一个轻量级 macOS 剪切板历史应用。它常驻菜单栏，监听系统剪切板里的文本和图片，并通过可配置的全局快捷键打开一个类似 Windows 剪切板历史的紧凑面板。

## 功能

- 菜单栏应用，不显示 Dock 图标
- 全局快捷键，默认 `⌃⌥V`
- 支持文本和图片剪切板历史
- 重复内容会移动到历史顶部
- 可配置历史保存数量，范围为 1 到 200 条
- 点击、双击或按回车键可把历史项复制回剪切板，并默认粘贴到原前台应用
- 自动粘贴需要 macOS 辅助功能权限；无权限时会退回为只复制到剪切板
- 使用 `UserDefaults` 在本地持久化历史记录和设置
- 使用 GitHub Actions 做 CI，并通过版本标签自动打包发布

## 环境要求

- macOS 13 或更高版本
- Swift 5.9 或更高版本

## 安装

### Homebrew

Homebrew Cask 会把 `cliplet.app` 安装到 `/Applications`：

```sh
brew tap IncredibleJ1021/cliplet https://github.com/IncredibleJ1021/cliplet.git
brew install --cask IncredibleJ1021/cliplet/cliplet
```

Homebrew 6.0 之后，第三方 tap 需要显式信任。如果安装时提示 untrusted tap，可只信任这个 cask 后再安装：

```sh
brew trust --cask IncredibleJ1021/cliplet/cliplet
brew install --cask IncredibleJ1021/cliplet/cliplet
```

更新和卸载：

```sh
brew upgrade --cask IncredibleJ1021/cliplet/cliplet
brew uninstall --cask cliplet
```

### GitHub Release

从 GitHub Release 下载 `cliplet-macOS-vX.Y.Z.dmg` 后，打开 DMG，把 `cliplet.app` 拖到 Applications。

如果下载的是 `cliplet-macOS-vX.Y.Z.zip`，解压只会得到 `cliplet.app`，不会自动安装。需要手动把它拖到 `/Applications`，或使用安装脚本：

```sh
curl -fsSL https://raw.githubusercontent.com/IncredibleJ1021/cliplet/main/scripts/install_latest.sh | bash
```

在新机器上首次打开时，macOS 可能需要从 Finder 中 Control-click `cliplet.app`，然后选择 Open。

### npm

cliplet 是原生 macOS 菜单栏应用，npm 包只作为安装器：它会下载 GitHub Release 里的 zip，并把 `cliplet.app` 复制到 `/Applications`。

不依赖 npm registry 时，可以直接从 GitHub 运行：

```sh
npx github:IncredibleJ1021/cliplet install
```

常用配置：

```sh
CLIPLET_VERSION=v0.4.0 npx github:IncredibleJ1021/cliplet install
CLIPLET_INSTALL_DIR="$HOME/Applications" npx github:IncredibleJ1021/cliplet install
npx github:IncredibleJ1021/cliplet open
npx github:IncredibleJ1021/cliplet uninstall
```

如果已发布到 npm registry，则可以这样安装：

```sh
npm install -g @incrediblej1021/cliplet
cliplet-installer install
```

卸载：

```sh
cliplet-installer uninstall
```

发布 npm 包需要先登录 npm，并确保 `package.json` 的版本号与要发布的应用版本一致：

```sh
npm login
npm publish --access public
```

## 开发

```sh
make build
make test
make run
make verify
npm run pack:check
```

## 本地打包

```sh
make package
open dist/cliplet.app
```

本地打包产物会使用 ad-hoc 签名，但不会经过 Apple 公证。在新机器上首次打开时，macOS 可能需要从 Finder 的右键菜单中打开一次。

生成带 Applications 快捷方式和拖拽提示背景的 DMG：

```sh
make dmg
```

## 发布

发布脚本要求工作树干净、当前分支为 `main` 且 `HEAD` 与 `origin/main` 完全一致。默认在本地运行完整测试：

```sh
./scripts/create_release_tag.sh v0.4.1
```

若发布机器只有 Command Line Tools、无法运行 XCTest，必须先推送 `main` 并等待同一提交的 GitHub CI 成功，再显式使用远端测试门禁：

```sh
CLIPLET_TEST_GATE=github SWIFT_BUILD_SYSTEM=native ./scripts/create_release_tag.sh v0.4.1
```

GitHub Actions 发布流程会构建 `cliplet.app`，进行 ad-hoc 签名，并上传 zip 与 DMG 到 GitHub 发布版本。
发布包包含 arm64 与 x86_64 两种架构，部署目标为 macOS 13.0。ad-hoc 签名不等于 Apple 公证；当前发布流程不会声称或提供 notarization。

## 当前范围

cliplet 会保存文本和图片剪切板条目。选择历史项后会把它复制回系统剪切板；默认会尝试恢复原前台应用并发送一次粘贴。这个行为可以在 Preferences 中关闭。由于 macOS 对模拟键盘输入有权限保护，自动粘贴需要在 System Settings > Privacy & Security > Accessibility 中授权 cliplet。
