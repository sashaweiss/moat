import Foundation

/// The host directories moat reads configuration from and stores state in.
public struct HostEnvironment: Sendable {
    public var homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    /// The host's `~/.claude`.
    public var claudeDirectory: URL {
        homeDirectory.appendingPathComponent(".claude")
    }

    /// `~/.moat`, where moat stores its settings and session state.
    public var moatDirectory: URL {
        homeDirectory.appendingPathComponent(".moat")
    }

    /// `~/.moat/settings.json`, which holds defaults for `SessionOptions`.
    public var settingsFile: URL {
        moatDirectory.appendingPathComponent("settings.json")
    }

    var sessionsDirectory: URL {
        moatDirectory.appendingPathComponent("sessions")
    }

    /// The metadata for the session whose workspace has `workspaceHash`.
    func metadataFile(workspaceHash: String) -> URL {
        sessionsDirectory.appendingPathComponent(
            "\(workspaceHash).metadata.json",
        )
    }

    // Because a Mac host can't easily share auth credentials with Claude in a
    // VM because of how it uses the keychain (see:
    // https://github.com/anthropics/claude-code/issues/1414), we'll store the
    // in-VM auth credentials in ~/.moat so we can share them across moat
    // sessions.
    var credentialsFile: URL {
        moatDirectory.appendingPathComponent("credentials.json")
    }
}
