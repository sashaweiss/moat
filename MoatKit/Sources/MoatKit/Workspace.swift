import Crypto
import Foundation

/// The folder a session works in: an absolute path, with symlinks resolved.
/// Sessions are keyed by their workspace.
public struct Workspace: Hashable, Sendable, Codable, CustomStringConvertible {
    public let path: String

    /// The workspace for `folder`, resolving symlinks. If `folder` doesn't
    /// exist, its path is used as given, made absolute.
    public init(folder: URL) {
        path = Filesystem.resolveSymlinks(folder.standardizedFileURL).path
    }

    /// Decodes a workspace as its path, trusting that it was encoded as a
    /// `Workspace`. Doesn't touch the filesystem, so a workspace that no
    /// longer exists still decodes.
    public init(from decoder: any Decoder) throws {
        path = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(path)
    }

    public var url: URL {
        URL(fileURLWithPath: path)
    }

    /// The workspace folder's name.
    public var name: String {
        url.lastPathComponent
    }

    public var description: String {
        path
    }

    /// The key for the workspace's state under `~/.moat/sessions`.
    var hash: String {
        SHA256.hash(data: Data(path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
            .description
    }

    /// The name of the workspace's VM: its folder name, to be recognizable,
    /// and its hash, to be unique. Characters other than ASCII alphanumerics,
    /// "_", and "-" are replaced with "-".
    var vmName: String {
        let folderName = String(name.map { character in
            if !character.isASCII {
                return "-"
            }
            if character.isLetter || character.isNumber || "_-".contains(character) {
                return character
            }
            return "-"
        })
        return "moat.\(folderName).\(hash)"
    }
}
