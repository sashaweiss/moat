import Foundation

public enum GitAccessMode: String, Codable, CaseIterable, Sendable {
    case read
    case write
}

/// Options for a moat session, as given by the user (e.g., as the
/// `sessionDefaults` in `~/.moat/settings.json`). Paths are unvalidated.
public struct SessionOptions: Equatable, Codable, Sendable {
    /// Claude Code permission mode.
    public var permissionMode: String = "auto"
    /// Claude model for the session.
    public var model: String = "opus"
    /// Whether to mount the git directory read-only or read-write.
    public var gitAccessMode: GitAccessMode = .read
    /// Number of CPUs for the VM.
    public var cpus: Int = 2
    /// Memory for the VM.
    public var memory: String = "4G"
    /// File of KEY=VALUE secrets to inject as environment variables.
    public var envFile: String?
    /// Skill directories to mount into the VM, in addition to the host's
    /// `~/.claude/skills`.
    public var addSkills: [String] = []
    /// Whether to skip seeding new sessions with the host's
    /// `~/.claude/settings.json`.
    public var noClaudeSettings: Bool = false

    public init() {}

    /// Decodes options, using the defaults for any that are missing.
    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        permissionMode = try container
            .decodeIfPresent(String.self, forKey: .permissionMode)
            ?? permissionMode
        model = try container
            .decodeIfPresent(String.self, forKey: .model)
            ?? model
        gitAccessMode = try container
            .decodeIfPresent(GitAccessMode.self, forKey: .gitAccessMode)
            ?? gitAccessMode
        cpus = try container
            .decodeIfPresent(Int.self, forKey: .cpus)
            ?? cpus
        memory = try container
            .decodeIfPresent(String.self, forKey: .memory)
            ?? memory
        envFile = try container
            .decodeIfPresent(String.self, forKey: .envFile)
        addSkills = try container
            .decodeIfPresent([String].self, forKey: .addSkills)
            ?? addSkills
        noClaudeSettings = try container
            .decodeIfPresent(Bool.self, forKey: .noClaudeSettings)
            ?? noClaudeSettings
    }
}
