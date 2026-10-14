import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

enum Git {
    /// Returns the common .git/ directory to mount for `workspace`, or nil if
    /// `workspace` isn't inside a git repo. This is the workspace's own .git/
    /// for a normal repo, or the original repo's shared .git/ for a worktree.
    static func commonDirectory(workspace: URL) async throws -> URL? {
        let result = try await run(
            .name("git"),
            arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"],
            workingDirectory: FilePath(workspace.path),
            output: .string(limit: Int(PATH_MAX)),
        )
        let path = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.terminationStatus.isSuccess, !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// Returns all .git/ directories at or below `root`. Doesn't include or
    /// follow symlinks.
    static func directories(root: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
            )
        else {
            return []
        }
        var gitDirectories: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == ".git" {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isDirectory == true else {
                continue
            }
            enumerator.skipDescendants()
            if values.isSymbolicLink != true {
                gitDirectories.append(url)
            }
        }
        return gitDirectories
    }
}
