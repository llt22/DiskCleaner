import CleanerCore
import Foundation

enum TestFailure: Error, CustomStringConvertible {
    case expectation(String)

    var description: String {
        switch self {
        case let .expectation(message): message
        }
    }
}

@main
struct CleanerServiceTests {
    static func main() throws {
        try scansAndCleansAllowlistedCache()
        try rejectsRuleOutsideCacheRoots()
        try reportsUnknownRule()
        try rejectsActiveDockerImages()
        try acceptsOnlyExplicitDeveloperCacheDescendants()
        try usesConservativeDefaults()
        try scansAndProtectsInstallerFiles()
        print("7 项安全边界测试全部通过")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure.expectation(message) }
    }

    static func scansAndCleansAllowlistedCache() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let temp = root.appendingPathComponent("var/T", isDirectory: true)
        let cache = home.appendingPathComponent("Library/Caches/example", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 32_768).write(to: cache.appendingPathComponent("cache.bin"))
        defer { try? FileManager.default.removeItem(at: root) }

        let rule = CleanupRule(
            id: "example",
            title: "测试缓存",
            detail: "测试",
            location: .home("Library/Caches/example")
        )
        let service = CleanerService(
            rules: [rule],
            homeDirectory: home,
            temporaryDirectory: temp
        )

        let scanned = service.scan()
        try expect(scanned.count == 1, "扫描结果数量不正确")
        try expect(scanned[0].exists, "未发现测试缓存")
        try expect(scanned[0].allocatedBytes > 0, "测试缓存大小应大于 0")

        let results = service.clean(ruleIDs: [rule.id])
        try expect(results[0].errorDescription == nil, "白名单缓存清理失败")
        try expect(!FileManager.default.fileExists(atPath: cache.path), "白名单缓存仍然存在")
    }

    static func rejectsRuleOutsideCacheRoots() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let temp = root.appendingPathComponent("var/T", isDirectory: true)
        let protected = home.appendingPathComponent("Documents/keep.txt")
        try FileManager.default.createDirectory(at: protected.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: protected)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let rule = CleanupRule(
            id: "unsafe",
            title: "不安全规则",
            detail: "测试",
            location: .home("Documents")
        )
        let service = CleanerService(
            rules: [rule],
            homeDirectory: home,
            temporaryDirectory: temp
        )

        let results = service.clean(ruleIDs: [rule.id])
        try expect(results[0].errorDescription != nil, "白名单外规则应明确失败")
        try expect(FileManager.default.fileExists(atPath: protected.path), "白名单外文件被误删")
    }

    static func reportsUnknownRule() throws {
        let service = CleanerService(rules: [])
        let results = service.clean(ruleIDs: ["missing"])
        try expect(results.count == 1, "未知规则结果数量不正确")
        try expect(
            results[0].errorDescription?.contains("未知清理规则") == true,
            "未知规则没有显式报错"
        )
    }

    static func rejectsActiveDockerImages() throws {
        let service = CleanerService()
        let results = service.cleanDocker(kinds: [.activeImages])
        try expect(results.count == 1, "Docker 拒绝结果数量不正确")
        try expect(results[0].errorDescription != nil, "正在使用的镜像应明确拒绝清理")
    }

    static func acceptsOnlyExplicitDeveloperCacheDescendants() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let temp = root.appendingPathComponent("var/T", isDirectory: true)
        let cache = home.appendingPathComponent(".npm/_cacache", isDirectory: true)
        let keep = home.appendingPathComponent(".npm/keep.txt")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: cache.appendingPathComponent("cache.bin"))
        try Data("keep".utf8).write(to: keep)
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheRule = CleanupRule(
            id: "npm-cache",
            title: "npm 缓存",
            detail: "测试",
            location: .home(".npm/_cacache")
        )
        let broadRule = CleanupRule(
            id: "npm-root",
            title: "npm 根目录",
            detail: "测试",
            location: .home(".npm")
        )
        let service = CleanerService(
            rules: [cacheRule, broadRule],
            homeDirectory: home,
            temporaryDirectory: temp
        )

        let results = service.clean(ruleIDs: [cacheRule.id, broadRule.id])
        try expect(
            results.first(where: { $0.id == cacheRule.id })?.errorDescription == nil,
            "明确的 npm 子缓存应允许清理"
        )
        try expect(
            results.first(where: { $0.id == broadRule.id })?.errorDescription != nil,
            "npm 根目录必须拒绝清理"
        )
        try expect(FileManager.default.fileExists(atPath: keep.path), "npm 根目录中的保留文件被误删")
    }

    static func usesConservativeDefaults() throws {
        let rules = CleanupRule.builtIn
        let lowRisk = rules.first(where: { $0.id == "npm-download-cache" })
        let caution = rules.first(where: { $0.id == "maven-repository" })
        try expect(lowRisk?.risk.isSelectedByDefault == true, "低风险缓存应默认选择")
        try expect(caution?.risk.isSelectedByDefault == false, "依赖仓库不应默认选择")
    }

    static func scansAndProtectsInstallerFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let nested = downloads.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let installer = downloads.appendingPathComponent("Example.dmg")
        let nestedInstaller = nested.appendingPathComponent("Keep.dmg")
        let document = downloads.appendingPathComponent("Keep.txt")
        try Data(repeating: 1, count: 8_192).write(to: installer)
        try Data("nested".utf8).write(to: nestedInstaller)
        try Data("document".utf8).write(to: document)
        defer { try? FileManager.default.removeItem(at: root) }

        let service = CleanerService(homeDirectory: home)
        let scanned = service.scanInstallers()
        try expect(scanned.errorDescription == nil, "安装包扫描不应失败")
        try expect(scanned.items.map(\.name) == ["Example.dmg"], "只应扫描下载目录顶层安装包")

        let rejected = service.cleanInstallers(urls: [nestedInstaller, document])
        try expect(rejected.allSatisfy { $0.errorDescription != nil }, "非顶层安装包必须拒绝")
        try expect(FileManager.default.fileExists(atPath: nestedInstaller.path), "嵌套安装包被误删")
        try expect(FileManager.default.fileExists(atPath: document.path), "普通文档被误删")

        let cleaned = service.cleanInstallers(urls: [installer])
        try expect(cleaned[0].errorDescription == nil, "顶层安装包清理失败")
        try expect(!FileManager.default.fileExists(atPath: installer.path), "顶层安装包仍然存在")
    }
}
