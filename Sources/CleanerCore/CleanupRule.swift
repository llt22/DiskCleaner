import Foundation

public enum RuleLocation: Sendable, Equatable {
    case home(String)
    case darwinTemporarySibling(directory: String, path: String)

    public func resolve(homeDirectory: URL, temporaryDirectory: URL) -> URL {
        switch self {
        case let .home(path):
            return homeDirectory.appendingPathComponent(path, isDirectory: true)
        case let .darwinTemporarySibling(directory, path):
            return temporaryDirectory
                .deletingLastPathComponent()
                .appendingPathComponent(directory, isDirectory: true)
                .appendingPathComponent(path, isDirectory: true)
        }
    }
}

public enum CleanupRisk: String, Sendable, Equatable {
    case low
    case caution
    case high

    public var isSelectedByDefault: Bool { self == .low }
}

public enum CleanupStrategy: Sendable, Equatable {
    case removeDirectory
    case command(executableCandidates: [String], arguments: [String])
}

public struct CleanupRule: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    public let location: RuleLocation
    public let blockingBundleIdentifiers: [String]
    public let risk: CleanupRisk
    public let strategy: CleanupStrategy

    public init(
        id: String,
        title: String,
        detail: String,
        location: RuleLocation,
        blockingBundleIdentifiers: [String] = [],
        risk: CleanupRisk = .low,
        strategy: CleanupStrategy = .removeDirectory
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.location = location
        self.blockingBundleIdentifiers = blockingBundleIdentifiers
        self.risk = risk
        self.strategy = strategy
    }
}

public extension CleanupRule {
    static let builtIn: [CleanupRule] = [
        CleanupRule(
            id: "wechat-cache",
            title: "微信缓存",
            detail: "仅清理缓存，不包含聊天记录和下载文件",
            location: .home("Library/Caches/com.tencent.xinWeChat"),
            blockingBundleIdentifiers: ["com.tencent.xinWeChat"]
        ),
        CleanupRule(
            id: "talkio-cache",
            title: "Talkio 缓存",
            detail: "Talkio 生成的可重建缓存",
            location: .home("Library/Caches/talkio")
        ),
        CleanupRule(
            id: "npm-download-cache",
            title: "npm 下载缓存",
            detail: "npm 下载的软件包缓存，不删除全局安装包",
            location: .home(".npm/_cacache")
        ),
        CleanupRule(
            id: "npx-cache",
            title: "npx 临时包",
            detail: "npx 临时安装的命令包，可按需重新下载",
            location: .home(".npm/_npx")
        ),
        CleanupRule(
            id: "prisma-cache",
            title: "Prisma 引擎缓存",
            detail: "Prisma 下载的引擎文件，可重新下载",
            location: .home(".cache/prisma")
        ),
        CleanupRule(
            id: "corepack-cache",
            title: "Corepack 缓存",
            detail: "Node.js 包管理器缓存，可重新下载",
            location: .home(".cache/node")
        ),
        CleanupRule(
            id: "pnpm-store",
            title: "pnpm 未引用包",
            detail: "通过 pnpm 官方命令回收未被项目引用的软件包",
            location: .home("Library/pnpm/store"),
            risk: .caution,
            strategy: .command(
                executableCandidates: ["/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm"],
                arguments: ["store", "prune"]
            )
        ),
        CleanupRule(
            id: "gradle-cache",
            title: "Gradle 构建缓存",
            detail: "请先停止构建；后续 Gradle 构建会重新下载和生成依赖",
            location: .home(".gradle/caches"),
            risk: .caution
        ),
        CleanupRule(
            id: "maven-repository",
            title: "Maven 本地仓库",
            detail: "会导致 Maven 项目重新下载全部依赖",
            location: .home(".m2/repository"),
            risk: .caution
        ),
        CleanupRule(
            id: "cargo-registry",
            title: "Cargo 注册表缓存",
            detail: "会导致 Rust 项目重新下载并解压依赖",
            location: .home(".cargo/registry"),
            risk: .caution
        ),
        CleanupRule(
            id: "google-cache",
            title: "Google 应用缓存",
            detail: "Chrome 等 Google 应用生成的可重建缓存",
            location: .home("Library/Caches/Google"),
            blockingBundleIdentifiers: ["com.google.Chrome"]
        ),
        CleanupRule(
            id: "playwright-cache",
            title: "Playwright 浏览器缓存",
            detail: "自动化测试下载的浏览器运行文件",
            location: .home("Library/Caches/ms-playwright")
        ),
        CleanupRule(
            id: "paseo-updater-cache",
            title: "Paseo 更新缓存",
            detail: "应用更新器下载的临时文件",
            location: .home("Library/Caches/@getpaseodesktop-updater")
        ),
        CleanupRule(
            id: "pnpm-cache",
            title: "pnpm 缓存",
            detail: "包管理器缓存，不删除项目依赖目录",
            location: .home("Library/Caches/pnpm")
        ),
        CleanupRule(
            id: "node-gyp-cache",
            title: "node-gyp 缓存",
            detail: "Node.js 原生模块编译缓存",
            location: .home("Library/Caches/node-gyp")
        ),
        CleanupRule(
            id: "lark-cache",
            title: "飞书缓存",
            detail: "飞书桌面端可重建缓存",
            location: .home("Library/Caches/LarkShell"),
            blockingBundleIdentifiers: ["com.electron.lark"]
        ),
        CleanupRule(
            id: "jetbrains-cache",
            title: "JetBrains 缓存",
            detail: "IDE 公共缓存，不删除项目或设置",
            location: .home("Library/Caches/JetBrains")
        ),
        CleanupRule(
            id: "homebrew-cache",
            title: "Homebrew 缓存",
            detail: "已下载的软件包和元数据缓存",
            location: .home("Library/Caches/Homebrew")
        ),
        CleanupRule(
            id: "chrome-code-sign-clone",
            title: "Chrome 临时代码副本",
            detail: "macOS 为 Chrome 创建的临时代码签名副本",
            location: .darwinTemporarySibling(
                directory: "X",
                path: "com.google.Chrome.code_sign_clone"
            ),
            blockingBundleIdentifiers: ["com.google.Chrome"]
        ),
    ]
}
