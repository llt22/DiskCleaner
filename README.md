# DiskCleaner

一个仅清理固定白名单缓存的原生 macOS 应用。使用 Swift 6 和 SwiftUI，不依赖 Xcode 工程或第三方库。

## 安全边界

- 只允许清理 `~/Library/Caches` 和当前用户 Darwin 临时目录下的内置规则。
- 不接受用户输入的删除路径。
- 不删除微信聊天记录、Chrome 用户资料、项目、容器或虚拟机数据。
- 删除前二次确认；相关应用运行时拒绝清理；失败会逐项报告。
- Docker 构建缓存默认可选；已停止容器和未使用卷默认不选。
- Docker 清理通过官方 CLI 执行，不直接删除 OrbStack 虚拟磁盘。

## 当前覆盖

- 应用缓存：微信、Google、飞书、Talkio、Paseo、JetBrains。
- Node.js：npm 下载缓存、npx 临时包、pnpm 未引用包、node-gyp、Prisma、Corepack。
- 开发依赖：Gradle、Maven、Cargo；默认不选择，清理后需要重新下载。
- 自动化与系统临时文件：Playwright、Homebrew、Chrome 临时代码副本。
- Docker：构建缓存、已停止容器、未使用镜像和数据卷；活动镜像仅展示。
- 安装包：扫描 `~/Downloads` 顶层的 DMG、PKG、XIP，逐文件展示且默认不选。
- 扫描过程按“缓存、Docker、安装包”显示阶段和进度。
- 清理过程逐项显示当前项目、完成数量和进度，结束后自动核对结果。

Android SDK、Rust/Python 工具链、Codex 运行时、聊天记录、浏览器资料及 OrbStack 虚拟磁盘不属于清理范围。

## 构建与运行

```bash
./scripts/test.sh
./scripts/build-app.sh
open build/DiskCleaner.app
```

当前机器的 SwiftPM 清单库与 Swift 编译器版本不匹配，因此构建脚本直接调用 `swiftc`。修复 Command Line Tools 后仍可使用项目内的 `Package.swift`。

应用使用本机临时签名，适合本机自用。对外分发需要 Apple Developer 证书和公证。
