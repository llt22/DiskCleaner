import Foundation

public struct ScanResult: Identifiable, Sendable, Equatable {
    public let rule: CleanupRule
    public let url: URL
    public let allocatedBytes: Int64
    public let exists: Bool
    public let errorDescription: String?

    public var id: String { rule.id }

    public init(
        rule: CleanupRule,
        url: URL,
        allocatedBytes: Int64,
        exists: Bool,
        errorDescription: String? = nil
    ) {
        self.rule = rule
        self.url = url
        self.allocatedBytes = allocatedBytes
        self.exists = exists
        self.errorDescription = errorDescription
    }
}

public struct CleanupResult: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let reclaimedBytes: Int64
    public let errorDescription: String?

    public init(id: String, title: String, reclaimedBytes: Int64, errorDescription: String?) {
        self.id = id
        self.title = title
        self.reclaimedBytes = reclaimedBytes
        self.errorDescription = errorDescription
    }
}

public enum DockerCleanupKind: String, CaseIterable, Sendable {
    case buildCache
    case stoppedContainers
    case unusedVolumes
    case unusedImages
    case activeImages

    public var title: String {
        switch self {
        case .buildCache: "Docker 构建缓存"
        case .stoppedContainers: "已停止的容器"
        case .unusedVolumes: "未使用的数据卷"
        case .unusedImages: "未使用的镜像"
        case .activeImages: "正在使用的镜像"
        }
    }

    public var detail: String {
        switch self {
        case .buildCache: "通过 Docker 回收构建缓存，可重新生成"
        case .stoppedContainers: "删除已停止容器，不影响运行中的容器"
        case .unusedVolumes: "可能包含数据库数据，清理前请确认"
        case .unusedImages: "没有容器引用的镜像，可在需要时重新下载"
        case .activeImages: "当前被容器使用，仅展示，不可删除"
        }
    }
}

public struct DockerScanResult: Identifiable, Sendable, Equatable {
    public let kind: DockerCleanupKind
    public let allocatedBytes: Int64
    public let available: Bool
    public let errorDescription: String?

    public var id: String { kind.rawValue }

    public init(
        kind: DockerCleanupKind,
        allocatedBytes: Int64,
        available: Bool,
        errorDescription: String? = nil
    ) {
        self.kind = kind
        self.allocatedBytes = allocatedBytes
        self.available = available
        self.errorDescription = errorDescription
    }
}

public enum CleanerError: LocalizedError, Equatable {
    case unknownRule(String)
    case unsafeTarget(String)
    case commandUnavailable(String)
    case commandFailed(String)
    case unsafeInstaller(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownRule(id):
            return "未知清理规则：\(id)"
        case let .unsafeTarget(path):
            return "目标不在允许的缓存目录中：\(path)"
        case let .commandUnavailable(title):
            return "找不到 \(title) 所需的清理命令"
        case let .commandFailed(title):
            return "\(title) 清理命令执行失败"
        case let .unsafeInstaller(path):
            return "安装包不在下载目录顶层或类型不受支持：\(path)"
        }
    }
}

public final class CleanerService: @unchecked Sendable {
    private let fileManager: FileManager
    private let rules: [CleanupRule]
    private let homeDirectory: URL
    private let temporaryDirectory: URL

    public init(
        fileManager: FileManager = .default,
        rules: [CleanupRule] = CleanupRule.builtIn,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.fileManager = fileManager
        self.rules = rules
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.temporaryDirectory = temporaryDirectory.standardizedFileURL
    }

    public func scan() -> [ScanResult] {
        rules.map { rule in
            let url = resolvedURL(for: rule)
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            do {
                return ScanResult(
                    rule: rule,
                    url: url,
                    allocatedBytes: exists ? try allocatedSize(at: url) : 0,
                    exists: exists
                )
            } catch {
                return ScanResult(
                    rule: rule,
                    url: url,
                    allocatedBytes: 0,
                    exists: exists,
                    errorDescription: error.localizedDescription
                )
            }
        }
    }

    public func clean(ruleIDs: Set<String>) -> [CleanupResult] {
        ruleIDs.sorted().map { id in
            guard let rule = rules.first(where: { $0.id == id }) else {
                return CleanupResult(
                    id: id,
                    title: id,
                    reclaimedBytes: 0,
                    errorDescription: CleanerError.unknownRule(id).localizedDescription
                )
            }

            let url = resolvedURL(for: rule)
            do {
                try validate(url: url, for: rule)
                let sizeBefore = try allocatedSize(at: url)
                switch rule.strategy {
                case .removeDirectory:
                    if fileManager.fileExists(atPath: url.path) {
                        try fileManager.removeItem(at: url)
                    }
                case let .command(executableCandidates, arguments):
                    guard let executable = executableCandidates.first(where: {
                        fileManager.isExecutableFile(atPath: $0)
                    }) else {
                        throw CleanerError.commandUnavailable(rule.title)
                    }
                    guard runCommand(executable: executable, arguments: arguments) != nil else {
                        throw CleanerError.commandFailed(rule.title)
                    }
                }
                let sizeAfter = try allocatedSize(at: url)
                return CleanupResult(
                    id: rule.id,
                    title: rule.title,
                    reclaimedBytes: max(0, sizeBefore - sizeAfter),
                    errorDescription: nil
                )
            } catch {
                return CleanupResult(
                    id: rule.id,
                    title: rule.title,
                    reclaimedBytes: 0,
                    errorDescription: error.localizedDescription
                )
            }
        }
    }

    public func scanInstallers() -> InstallerScanSummary {
        let downloads = homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .contentModificationDateKey,
        ]
        do {
            let urls = try fileManager.contentsOfDirectory(
                at: downloads,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
            let items = try urls.compactMap { url -> InstallerArtifact? in
                guard Self.installerExtensions.contains(url.pathExtension.lowercased()) else {
                    return nil
                }
                let values = try url.resourceValues(forKeys: keys)
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    return nil
                }
                return InstallerArtifact(
                    url: url.standardizedFileURL,
                    allocatedBytes: Int64(
                        values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
                    ),
                    modifiedAt: values.contentModificationDate
                )
            }.sorted { $0.allocatedBytes > $1.allocatedBytes }
            return InstallerScanSummary(items: items)
        } catch {
            return InstallerScanSummary(items: [], errorDescription: error.localizedDescription)
        }
    }

    public func cleanInstallers(urls: Set<URL>) -> [CleanupResult] {
        urls.sorted { $0.path < $1.path }.map { inputURL in
            let url = inputURL.standardizedFileURL
            do {
                try validateInstaller(url)
                let values = try url.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .totalFileAllocatedSizeKey,
                    .fileAllocatedSizeKey,
                ])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw CleanerError.unsafeInstaller(url.path)
                }
                let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                try fileManager.removeItem(at: url)
                return CleanupResult(
                    id: url.path,
                    title: url.lastPathComponent,
                    reclaimedBytes: size,
                    errorDescription: nil
                )
            } catch {
                return CleanupResult(
                    id: url.path,
                    title: url.lastPathComponent,
                    reclaimedBytes: 0,
                    errorDescription: error.localizedDescription
                )
            }
        }
    }

    private func validateInstaller(_ url: URL) throws {
        let downloads = homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
            .standardizedFileURL
        guard url.deletingLastPathComponent() == downloads,
              Self.installerExtensions.contains(url.pathExtension.lowercased()) else {
            throw CleanerError.unsafeInstaller(url.path)
        }
    }

    private static let installerExtensions: Set<String> = ["dmg", "pkg", "xip"]

    private func resolvedURL(for rule: CleanupRule) -> URL {
        rule.location.resolve(
            homeDirectory: homeDirectory,
            temporaryDirectory: temporaryDirectory
        ).standardizedFileURL
    }

    private func validate(url: URL, for rule: CleanupRule) throws {
        let expected = resolvedURL(for: rule)
        guard url == expected else {
            throw CleanerError.unknownRule(rule.id)
        }

        let broadRoots = [
            homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true),
            homeDirectory.appendingPathComponent(".npm", isDirectory: true),
            homeDirectory.appendingPathComponent(".cache", isDirectory: true),
        ].map(\.standardizedFileURL)
        let exactRoots = [
            homeDirectory.appendingPathComponent(".gradle/caches", isDirectory: true),
            homeDirectory.appendingPathComponent(".m2/repository", isDirectory: true),
            homeDirectory.appendingPathComponent(".cargo/registry", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/pnpm/store", isDirectory: true),
        ].map(\.standardizedFileURL)
        let darwinXRoot = temporaryDirectory.deletingLastPathComponent()
            .appendingPathComponent("X", isDirectory: true)
            .standardizedFileURL
        guard broadRoots.contains(where: { url.isStrictDescendant(of: $0) })
                || exactRoots.contains(url)
                || url.isStrictDescendant(of: darwinXRoot) else {
            throw CleanerError.unsafeTarget(url.path)
        }
    }

    private func allocatedSize(at root: URL) throws -> Int64 {
        guard fileManager.fileExists(atPath: root.path) else { return 0 }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
        ]
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            return try resourceAllocatedSize(at: root, keys: keys)
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        if let enumerationError { throw enumerationError }
        return total
    }

    private func resourceAllocatedSize(at url: URL, keys: Set<URLResourceKey>) throws -> Int64 {
        let values = try url.resourceValues(forKeys: keys)
        guard values.isRegularFile == true else {
            return 0
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    public func scanDocker() -> [DockerScanResult] {
        let fallback = DockerCleanupKind.allCases.map {
            DockerScanResult(
                kind: $0,
                allocatedBytes: 0,
                available: false,
                errorDescription: "找不到 Docker，或 Docker 后端未运行"
            )
        }
        guard let output = runDocker(arguments: ["system", "df", "--format", "{{json .}}"]) else {
            return fallback
        }

        var results = Dictionary(uniqueKeysWithValues: fallback.map { ($0.id, $0) })
        for line in output.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let row = try? JSONDecoder().decode(DockerDFRow.self, from: data) else { continue }
            let reclaimable = parseBytes(row.reclaimable)
            if row.type == "Images" {
                results[DockerCleanupKind.activeImages.rawValue] = DockerScanResult(
                    kind: .activeImages,
                    allocatedBytes: parseBytes(row.size),
                    available: false
                )
                results[DockerCleanupKind.unusedImages.rawValue] = DockerScanResult(
                    kind: .unusedImages,
                    allocatedBytes: reclaimable,
                    available: true
                )
                continue
            }
            guard let kind = DockerCleanupKind(row: row.type) else { continue }
            let size = reclaimable > 0 ? reclaimable : parseBytes(row.size)
            let available = kind != .activeImages
            results[kind.rawValue] = DockerScanResult(
                kind: kind,
                allocatedBytes: size,
                available: available
            )
        }
        return DockerCleanupKind.allCases.compactMap { results[$0.rawValue] }
    }

    public func cleanDocker(kinds: Set<DockerCleanupKind>) -> [CleanupResult] {
        kinds.sorted { $0.rawValue < $1.rawValue }.map { kind in
            guard kind != .activeImages else {
                return CleanupResult(
                    id: kind.rawValue,
                    title: kind.title,
                    reclaimedBytes: 0,
                    errorDescription: "正在使用的镜像不可清理"
                )
            }
            let arguments: [String]
            switch kind {
            case .buildCache: arguments = ["builder", "prune", "--all", "--force"]
            case .stoppedContainers: arguments = ["container", "prune", "--force"]
            case .unusedVolumes: arguments = ["volume", "prune", "--all", "--force"]
            case .unusedImages: arguments = ["image", "prune", "--all", "--force"]
            case .activeImages: arguments = []
            }
            guard let output = runDocker(arguments: arguments) else {
                return CleanupResult(
                    id: kind.rawValue,
                    title: kind.title,
                    reclaimedBytes: 0,
                    errorDescription: "找不到 Docker，或 Docker 后端未运行"
                )
            }
            return CleanupResult(
                id: kind.rawValue,
                title: kind.title,
                reclaimedBytes: parseReclaimedFromOutput(output),
                errorDescription: nil
            )
        }
    }

    private func runDocker(arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            homeDirectory.appendingPathComponent(".orbstack/bin/docker").path,
        ]
        guard let executable = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func runCommand(executable: String, arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func parseReclaimedFromOutput(_ output: String) -> Int64 {
        output.split(separator: "\n")
            .first(where: { $0.localizedCaseInsensitiveContains("total reclaimed space") })
            .map { parseBytes(String($0).components(separatedBy: ":").last ?? "") } ?? 0
    }

    private func parseBytes(_ value: String) -> Int64 {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(B|KB|MB|GB|TB)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: normalized,
                range: NSRange(normalized.startIndex..., in: normalized)
              ),
              let numberRange = Range(match.range(at: 1), in: normalized),
              let unitRange = Range(match.range(at: 2), in: normalized),
              let number = Double(normalized[numberRange]) else { return 0 }
        let multiplier: Double
        switch normalized[unitRange].uppercased() {
        case "TB": multiplier = 1_000_000_000_000
        case "GB": multiplier = 1_000_000_000
        case "MB": multiplier = 1_000_000
        case "KB": multiplier = 1_000
        default: multiplier = 1
        }
        return Int64(number * multiplier)
    }

    private struct DockerDFRow: Decodable {
        let type: String
        let totalCount: String?
        let active: String?
        let size: String
        let reclaimable: String

        enum CodingKeys: String, CodingKey {
            case type = "Type"
            case totalCount = "TotalCount"
            case active = "Active"
            case size = "Size"
            case reclaimable = "Reclaimable"
        }
    }
}

private extension DockerCleanupKind {
    init?(row: String) {
        switch row {
        case "Containers": self = .stoppedContainers
        case "Build Cache": self = .buildCache
        case "Local Volumes": self = .unusedVolumes
        default: return nil
        }
    }
}

private extension URL {
    func isStrictDescendant(of parent: URL) -> Bool {
        let parentComponents = parent.standardizedFileURL.pathComponents
        let components = standardizedFileURL.pathComponents
        return components.count > parentComponents.count
            && Array(components.prefix(parentComponents.count)) == parentComponents
    }
}
