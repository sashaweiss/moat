import Foundation

enum Filesystem {
    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    static func isFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    /// Returns `url` with symlinks resolved via realpath(3), or `url` unchanged
    /// if it doesn't exist.
    ///
    /// `URL.resolvingSymlinksInPath()` strips leading /private on macOS (e.g.,
    /// /private/tmp becomes tmp). git and the shell give real paths, so it's
    /// safer to canonicalize via realpath.
    static func resolveSymlinks(_ url: URL) -> URL {
        guard let resolved = realpath(url.path, nil) else {
            return url
        }
        defer { free(resolved) }
        return URL(
            fileURLWithPath: String(cString: resolved),
            isDirectory: url.hasDirectoryPath,
        )
    }
}
