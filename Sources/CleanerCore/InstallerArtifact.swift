import Foundation

public struct InstallerArtifact: Identifiable, Sendable, Equatable {
    public let url: URL
    public let allocatedBytes: Int64
    public let modifiedAt: Date?

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public var fileExtension: String { url.pathExtension.lowercased() }

    public init(url: URL, allocatedBytes: Int64, modifiedAt: Date?) {
        self.url = url
        self.allocatedBytes = allocatedBytes
        self.modifiedAt = modifiedAt
    }
}

public struct InstallerScanSummary: Sendable, Equatable {
    public let items: [InstallerArtifact]
    public let errorDescription: String?

    public init(items: [InstallerArtifact], errorDescription: String? = nil) {
        self.items = items
        self.errorDescription = errorDescription
    }
}
