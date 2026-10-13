import Foundation

public enum GitAccessMode: String, Codable, CaseIterable {
    case read
    case write
}

/// Options for a moat session, as given by the user. Paths are unvalidated
/// and may be relative or start with `~`.
public struct SessionOptions: Equatable {
    /// Directory to mount as the workspace in the VM.
    public var workspace: String
    /// Claude Code permission mode.
    public var permissionMode: String = "auto"
    /// Claude model for the session.
    public var model: String = "opus"
    /// Whether to mount the git directory read-only or read-write.
    public var gitAccessMode: GitAccessMode = .read
    /// File of KEY=VALUE secrets to inject as environment variables.
    public var envFile: String?
    /// Skill directories to mount into the VM, in addition to the host's
    /// `~/.claude/skills`.
    public var additionalSkills: [String] = []
    /// Whether to seed new sessions with the host's `~/.claude/settings.json`.
    public var seedsClaudeSettings: Bool = true
    /// Additional arguments forwarded to `claude` inside the VM.
    public var claudeArguments: [String] = []

    public init(workspace: String) {
        self.workspace = workspace
    }
}

/// Defaults for `SessionOptions`, read from `~/.moat/settings.json`.
public struct MoatSettings: Equatable, Decodable {
    public var addSkills: [String]?
    public var envFile: String?
    public var gitAccessMode: GitAccessMode?
    public var model: String?
    public var noClaudeSettings: Bool?
    public var permissionMode: String?

    public init() {}

    /// Loads settings from `url`, or returns empty settings if it doesn't
    /// exist.
    public static func load(from url: URL) throws -> MoatSettings {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return MoatSettings()
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(MoatSettings.self, from: data)
        } catch {
            throw MoatError.invalidSettingsFile(url.path)
        }
    }

    /// Apply these settings to `options`.
    public func apply(to options: inout SessionOptions) {
        if let addSkills {
            options.additionalSkills += addSkills
        }
        if let envFile {
            options.envFile = envFile
        }
        if let gitAccessMode {
            options.gitAccessMode = gitAccessMode
        }
        if let model {
            options.model = model
        }
        if noClaudeSettings == true {
            options.seedsClaudeSettings = false
        }
        if let permissionMode {
            options.permissionMode = permissionMode
        }
    }
}
