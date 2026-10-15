import Foundation

/// What moat records about a session, in `~/.moat/sessions/<hash>.metadata.json`.
/// Not mounted into the VM.
public struct SessionMetadata: Codable, Equatable, Sendable {
    /// The workspace's absolute path, with symlinks resolved.
    public var workspace: String
    /// A name to show for the session; defaults to the workspace's name.
    public var name: String

    public init(workspace: String, name: String) {
        self.workspace = workspace
        self.name = name
    }

    /// Loads metadata from `url`.
    public static func load(file url: URL) throws -> SessionMetadata {
        try JSONDecoder().decode(
            SessionMetadata.self,
            from: Data(contentsOf: url),
        )
    }

    /// Writes this metadata to `url`.
    public func write(file url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        try encoder.encode(self).write(to: url)
    }
}
