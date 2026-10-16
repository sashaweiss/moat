import Foundation

/// Where moat finds its tools on this Mac, from the top level of
/// `~/.moat/settings.json`.
public struct HostSettings: Equatable, Codable, Sendable {
    /// Path to a `container` executable.
    public var containerPath: String = "/usr/local/bin/container"
    /// Path to a `git` executable.
    public var gitPath: String = "/usr/bin/git"

    public init() {}

    /// Decodes settings, using the defaults for any that are missing.
    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        containerPath = try container
            .decodeIfPresent(String.self, forKey: .containerPath)
            ?? containerPath
        gitPath = try container
            .decodeIfPresent(String.self, forKey: .gitPath)
            ?? gitPath
    }
}
