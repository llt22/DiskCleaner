import CleanerCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = CleanerViewModel()
    @State private var showingConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.isScanning {
                operationProgress(
                    title: model.scanPhase.title,
                    progress: model.scanPhase.progress,
                    trailingText: "\(Int(model.scanPhase.progress * 100))%",
                    tint: .accentColor
                )
            } else if model.isCleaning {
                operationProgress(
                    title: model.cleanupTitle,
                    progress: model.cleanupProgress,
                    trailingText: "\(model.cleanupCompletedCount) / \(model.cleanupTotalCount)",
                    tint: .orange
                )
            }
            Divider()
            itemList
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { model.scan(selectFoundItems: true) }
        .confirmationDialog(
            "确认清理所选项目？",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("执行清理 · \(ByteCount.string(model.selectedBytes))", role: .destructive) {
                model.cleanSelected()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text(confirmationMessage)
        }
        .alert("无法清理", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("知道了") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.gradient)
                Image(systemName: "externaldrive.fill.badge.checkmark")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("磁盘清理器")
                    .font(.title2.weight(.semibold))
                Text("缓存与 Docker 可回收资源，默认只选择低风险项")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(ByteCount.string(model.foundBytes))
                    .font(.title2.monospacedDigit().weight(.semibold))
                Text("可管理空间")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    private var itemList: some View {
        Group {
            if model.isScanning && model.items.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(model.scanPhase.title)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("应用与开发缓存") {
                        ForEach(model.items) { item in
                            cacheRow(item)
                        }
                    }
                    Section("Docker · OrbStack") {
                        ForEach(model.dockerItems) { item in
                            dockerRow(item)
                        }
                    }
                    Section("下载目录 · 安装包") {
                        if let error = model.installerError {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        } else if model.installerItems.isEmpty {
                            Text("没有发现 .dmg、.pkg 或 .xip 文件")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.installerItems) { item in
                                installerRow(item)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func operationProgress(
        title: String,
        progress: Double,
        trailingText: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(tint)
                .frame(maxWidth: 220)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(trailingText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(tint.opacity(0.06))
    }

    private func cacheRow(_ item: ScanResult) -> some View {
        HStack(spacing: 14) {
                        Toggle("", isOn: Binding(
                            get: { model.selectedIDs.contains(item.id) },
                            set: { _ in model.toggle(item.id) }
                        ))
                        .labelsHidden()
                        .disabled(item.allocatedBytes == 0 || model.isWorking)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.rule.title)
                                .fontWeight(.medium)
                            if item.rule.risk == .caution {
                                Text("需重新下载")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                            Text(item.errorDescription ?? item.rule.detail)
                                .font(.caption)
                                .foregroundStyle(item.errorDescription == nil ? Color.secondary : Color.red)
                        }

                        Spacer()

                        Text(item.errorDescription != nil
                             ? "扫描失败"
                             : (item.allocatedBytes == 0 ? "无缓存" : ByteCount.string(item.allocatedBytes)))
                            .monospacedDigit()
                            .foregroundStyle(item.allocatedBytes == 0 ? .tertiary : .primary)
        }
        .padding(.vertical, 6)
    }

    private func dockerRow(_ item: DockerScanResult) -> some View {
        HStack(spacing: 14) {
            Toggle("", isOn: Binding(
                get: { model.selectedDockerKinds.contains(item.kind) },
                set: { _ in model.toggleDocker(item.kind) }
            ))
            .labelsHidden()
            .disabled(!item.available || item.allocatedBytes == 0 || model.isWorking)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.kind.title).fontWeight(.medium)
                    if item.kind == .unusedVolumes || item.kind == .unusedImages {
                        Text(item.kind == .unusedVolumes ? "高风险" : "需重新下载")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(item.errorDescription ?? item.kind.detail)
                    .font(.caption)
                    .foregroundStyle(item.errorDescription == nil ? Color.secondary : Color.red)
            }
            Spacer()
            Text(item.errorDescription != nil
                 ? "扫描失败"
                 : (item.allocatedBytes == 0 ? "无可回收" : ByteCount.string(item.allocatedBytes)))
                .monospacedDigit()
                .foregroundStyle(item.available && item.allocatedBytes > 0 ? .primary : .tertiary)
        }
        .padding(.vertical, 6)
    }

    private func installerRow(_ item: InstallerArtifact) -> some View {
        HStack(spacing: 14) {
            Toggle("", isOn: Binding(
                get: { model.selectedInstallerIDs.contains(item.id) },
                set: { _ in model.toggleInstaller(item.id) }
            ))
            .labelsHidden()
            .disabled(model.isWorking)

            Image(systemName: installerIcon(for: item.fileExtension))
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.fileExtension.uppercased())
                    if let date = item.modifiedAt {
                        Text("·")
                        Text(date, format: .dateTime.year().month().day())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteCount.string(item.allocatedBytes))
                .monospacedDigit()
        }
        .padding(.vertical, 6)
    }

    private func installerIcon(for fileExtension: String) -> String {
        fileExtension == "pkg" ? "shippingbox.fill" : "archivebox.fill"
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if !model.lastResults.isEmpty {
                resultSummary
            }

            HStack {
                Button {
                    model.scan()
                } label: {
                    Label("重新扫描", systemImage: "arrow.clockwise")
                }
                .disabled(model.isWorking)

                Spacer()

                Text("已选择 \(ByteCount.string(model.selectedBytes))")
                    .foregroundStyle(.secondary)

                Button("清理所选…") {
                    showingConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.selectedBytes == 0 || model.isWorking)
            }
        }
        .padding(20)
    }

    private var resultSummary: some View {
        let failures = model.lastResults.compactMap(\.errorDescription)
        let reclaimed = model.lastResults.reduce(0) { $0 + $1.reclaimedBytes }
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(failures.isEmpty ? .green : .orange)
            Text(failures.isEmpty
                 ? "清理完成，已处理 \(ByteCount.string(reclaimed)) 可重建数据"
                 : "部分项目失败：\(failures.joined(separator: "；"))")
                .font(.callout)
            Spacer()
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private var confirmationMessage: String {
        if model.hasInstallerSelection {
            return "包含下载目录中的安装包文件。它们将被永久删除且无法撤销，请确认不再需要重新安装。"
        }
        if model.selectedDockerKinds.contains(.unusedVolumes) {
            return "包含全部未使用的 Docker 数据卷，其中可能存有数据库数据。删除无法撤销，请确认已备份。"
        }
        if model.selectedDockerKinds.contains(.unusedImages) {
            return "将删除没有容器引用的 Docker 镜像。后续使用时需要重新下载或构建。"
        }
        if model.hasCautionSelection {
            return "包含开发依赖仓库。清理后不会删除项目源码，但后续构建需要重新下载依赖，请确认网络可用。"
        }
        if !model.selectedDockerKinds.isEmpty {
            return "将通过 Docker 自身接口清理所选资源，删除无法撤销；运行中的容器和镜像不会被删除。"
        }
        return "缓存可重新生成，但本次删除无法撤销。不会清理聊天记录、浏览器资料、项目或容器数据。"
    }
}
