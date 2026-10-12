import Foundation

enum Git {
    /// Returns the common .git/ directory to mount for `workspace`, or nil if
    /// `workspace` isn't inside a git repo. This is the workspace's own .git/
    /// for a normal repo, or the original repo's shared .git/ for a worktree.
    static func commonDirectory(for workspace: URL) throws -> URL? {
        let output = Pipe()
        let status = try run(
            ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
            in: workspace,
            standardOutput: output,
        )
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == 0, !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// Returns all .git/ directories at or below `root`. Doesn't include or
    /// follow symlinks.
    static func directories(under root: URL) throws -> [URL] {
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
