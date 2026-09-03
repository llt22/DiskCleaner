import AppKit
import CleanerCore
import Combine
import Foundation

enum ScanPhase: Equatable {
    case idle
    case caches
    case docker
    case installers
    case finished

    var title: String {
        switch self {
        case .idle: "准备扫描…"
        case .caches: "扫描应用与开发缓存…"
        case .docker: "读取 Docker / OrbStack…"
        case .installers: "扫描下载目录中的安装包…"
        case .finished: "扫描完成"
        }
    }

    var progress: Double {
        switch self {
        case .idle: 0
        case .caches: 0.25
        case .docker: 0.55
        case .installers: 0.8
        case .finished: 1
        }
    }
}

@MainActor
final class CleanerViewModel: ObservableObject {
    @Published private(set) var items: [ScanResult] = []
    @Published private(set) var dockerItems: [DockerScanResult] = []
    @Published private(set) var installerItems: [InstallerArtifact] = []
    @Published var selectedInstallerIDs: Set<String> = []
    @Published private(set) var installerError: String?
    @Published private(set) var scanPhase: ScanPhase = .idle
    @Published var selectedIDs: Set<String> = []
    @Published var selectedDockerKinds: Set<DockerCleanupKind> = []
    @Published private(set) var isWorking = false
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var cleanupTitle = ""
    @Published private(set) var cleanupProgress = 0.0
    @Published private(set) var cleanupCompletedCount = 0
    @Published private(set) var cleanupTotalCount = 0
    @Published private(set) var lastResults: [CleanupResult] = []
    @Published var errorMessage: String?

    private let service = CleanerService()

    var selectedBytes: Int64 {
        let cacheBytes = items.filter { selectedIDs.contains($0.id) }
            .reduce(0) { $0 + $1.allocatedBytes }
        let dockerBytes = dockerItems.filter { selectedDockerKinds.contains($0.kind) }
            .reduce(0) { $0 + $1.allocatedBytes }
        let installerBytes = installerItems.filter { selectedInstallerIDs.contains($0.id) }
            .reduce(0) { $0 + $1.allocatedBytes }
        return cacheBytes + dockerBytes + installerBytes
    }

    var foundBytes: Int64 {
        items.reduce(0) { $0 + $1.allocatedBytes }
            + dockerItems.filter(\.available).reduce(0) { $0 + $1.allocatedBytes }
            + installerItems.reduce(0) { $0 + $1.allocatedBytes }
    }

    var selectedItems: [ScanResult] {
        items.filter { selectedIDs.contains($0.id) && $0.allocatedBytes > 0 }
    }

    var hasCautionSelection: Bool {
        selectedItems.contains { $0.rule.risk == .caution }
    }

    var hasInstallerSelection: Bool { !selectedInstallerIDs.isEmpty }

    func scan(selectFoundItems: Bool = false) {
        isWorking = true
        isScanning = true
        scanPhase = .caches
        lastResults = []
        Task {
            let scanned = await Task.detached { [service] in service.scan() }.value
            items = scanned.sorted { $0.allocatedBytes > $1.allocatedBytes }
            scanPhase = .docker
            let docker = await Task.detached { [service] in service.scanDocker() }.value
            dockerItems = docker
            scanPhase = .installers
            let installers = await Task.detached { [service] in service.scanInstallers() }.value
            installerItems = installers.items
            installerError = installers.errorDescription
            if selectFoundItems {
                selectedIDs = Set(scanned.filter {
                    $0.allocatedBytes > 0 && $0.rule.risk.isSelectedByDefault
                }.map(\.id))
                selectedDockerKinds = Set(
                    docker.filter { $0.kind == .buildCache && $0.allocatedBytes > 0 }.map(\.kind)
                )
                selectedInstallerIDs.removeAll()
            } else {
                selectedIDs = selectedIDs.intersection(Set(scanned.filter { $0.allocatedBytes > 0 }.map(\.id)))
                selectedDockerKinds = selectedDockerKinds.intersection(
                    Set(docker.filter { $0.available && $0.allocatedBytes > 0 }.map(\.kind))
                )
                selectedInstallerIDs = selectedInstallerIDs.intersection(Set(installers.items.map(\.id)))
            }
            scanPhase = .finished
            isScanning = false
            isWorking = false
        }
    }

    func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    func toggleDocker(_ kind: DockerCleanupKind) {
        if selectedDockerKinds.contains(kind) {
            selectedDockerKinds.remove(kind)
        } else {
            selectedDockerKinds.insert(kind)
        }
    }

    func toggleInstaller(_ id: String) {
        if selectedInstallerIDs.contains(id) {
            selectedInstallerIDs.remove(id)
        } else {
            selectedInstallerIDs.insert(id)
        }
    }

    func cleanSelected() {
        let selected = selectedItems
        let blockers = runningApplications(for: selected)
        guard blockers.isEmpty else {
            errorMessage = "请先退出这些应用：\(blockers.sorted().joined(separator: "、"))"
            return
        }

        let dockerKinds = selectedDockerKinds.sorted { $0.rawValue < $1.rawValue }
        let installers = installerItems.filter {
            selectedInstallerIDs.contains($0.id)
        }
        let totalCount = selected.count + dockerKinds.count + installers.count
        guard totalCount > 0 else { return }
        isWorking = true
        isCleaning = true
        cleanupProgress = 0
        cleanupCompletedCount = 0
        cleanupTotalCount = totalCount
        Task {
            var results: [CleanupResult] = []

            for item in selected {
                cleanupTitle = "正在清理 \(item.rule.title)…"
                let result = await Task.detached { [service] in
                    service.clean(ruleIDs: [item.id])
                }.value
                results.append(contentsOf: result)
                advanceCleanupProgress()
            }

            for kind in dockerKinds {
                cleanupTitle = "正在清理 \(kind.title)…"
                let result = await Task.detached { [service] in
                    service.cleanDocker(kinds: [kind])
                }.value
                results.append(contentsOf: result)
                advanceCleanupProgress()
            }

            for installer in installers {
                cleanupTitle = "正在删除 \(installer.name)…"
                let result = await Task.detached { [service] in
                    service.cleanInstallers(urls: [installer.url])
                }.value
                results.append(contentsOf: result)
                advanceCleanupProgress()
            }

            lastResults = results
            cleanupTitle = "正在核对清理结果…"
            let scanned = await Task.detached { [service] in service.scan() }.value
            items = scanned.sorted { $0.allocatedBytes > $1.allocatedBytes }
            let docker = await Task.detached { [service] in service.scanDocker() }.value
            dockerItems = docker
            let installers = await Task.detached { [service] in service.scanInstallers() }.value
            installerItems = installers.items
            installerError = installers.errorDescription
            selectedIDs.removeAll()
            selectedDockerKinds.removeAll()
            selectedInstallerIDs.removeAll()
            cleanupProgress = 1
            isCleaning = false
            isWorking = false
        }
    }

    private func advanceCleanupProgress() {
        cleanupCompletedCount += 1
        cleanupProgress = Double(cleanupCompletedCount) / Double(max(cleanupTotalCount, 1))
    }

    private func runningApplications(for items: [ScanResult]) -> Set<String> {
        let bundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Set(items.flatMap { item in
            item.rule.blockingBundleIdentifiers.compactMap { bundleID in
                bundleIDs.contains(bundleID) ? item.rule.title : nil
            }
        })
    }
}
