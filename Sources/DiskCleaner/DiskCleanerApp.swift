import AppKit
import SwiftUI

@main
struct DiskCleanerApp: App {
    @NSApplicationDelegateAdaptor(SnapshotAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 760, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

@MainActor
final class SnapshotAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let optionIndex = arguments.firstIndex(of: "--snapshot"),
              arguments.indices.contains(optionIndex + 1) else {
            return
        }

        let outputURL = URL(fileURLWithPath: arguments[optionIndex + 1])
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            do {
                try captureMainWindow(to: outputURL)
            } catch {
                FileHandle.standardError.write(Data("截图失败：\(error.localizedDescription)\n".utf8))
            }
            NSApplication.shared.terminate(nil)
        }
    }

    private func captureMainWindow(to outputURL: URL) throws {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }),
              let contentView = window.contentView else {
            throw SnapshotError.windowUnavailable
        }
        window.setContentSize(NSSize(width: 900, height: 900))
        contentView.layoutSubtreeIfNeeded()
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            throw SnapshotError.windowUnavailable
        }

        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.encodingFailed
        }
        try png.write(to: outputURL, options: .atomic)
    }
}

enum SnapshotError: LocalizedError {
    case windowUnavailable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .windowUnavailable: "应用窗口不可用"
        case .encodingFailed: "无法编码 PNG 图片"
        }
    }
}
