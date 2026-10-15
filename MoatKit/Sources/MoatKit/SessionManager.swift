import Foundation

/// Manages moat's sessions, persisted in `~/.moat/sessions`.
@MainActor
public final class SessionManager {
    public static let shared = SessionManager(environment: HostEnvironment())

    public let environment: HostEnvironment

    public init(environment: HostEnvironment) {
        self.environment = environment
    }

    /// Returns the metadata of every session in `~/.moat/sessions`, sorted
    /// by name.
    public func list() throws -> [SessionMetadata] {
        let sessionsDirectory = environment.sessionsDirectory
        guard Filesystem.isDirectory(sessionsDirectory) else {
            return []
        }
        let metadataFiles = try FileManager.default
            .contentsOfDirectory(
                at: sessionsDirectory,
                includingPropertiesForKeys: nil,
            )
            .filter { $0.lastPathComponent.hasSuffix(".metadata.json") }
        let sessions = try metadataFiles.map { metadataFile in
            try SessionMetadata.load(file: metadataFile)
        }
        return sessions.sorted { first, second in
            first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }
}
