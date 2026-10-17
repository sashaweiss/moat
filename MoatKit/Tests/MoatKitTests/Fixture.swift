import Foundation
import Subprocess
@testable import MoatKit
#if canImport(System)
import System
#else
import SystemPackage
#endif

/// The path in `error`, if it's `MoatError.invalidSettingsFile`.
func invalidSettingsFilePath(_ error: MoatError?) -> String? {
    switch error {
    case .invalidSettingsFile(let path, _):
        path
    default:
        nil
    }
}

/// A scratch directory with a fake home and workspace, removed on deinit.
final class Fixture {
    let root: URL
    let home: URL
    let workspace: URL

    init() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MoatKitTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = Filesystem.resolveSymlinks(root)
        home = self.root.appendingPathComponent("home")
        workspace = self.root.appendingPathComponent("workspace")
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var environment: HostEnvironment {
        HostEnvironment(homeDirectory: home)
    }

    func guestVM() -> GuestVM {
        GuestVM(environment: environment)
    }

    @discardableResult
    func makeDirectory(_ path: String, base: URL? = nil) throws -> URL {
        let url = (base ?? root).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func write(_ contents: String, path: String, base: URL? = nil) throws -> URL {
        let url = (base ?? root).appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try contents.write(to: url, atomically: false, encoding: .utf8)
        return url
    }

    func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func readJSON(_ url: URL) throws -> NSDictionary {
        try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! NSDictionary
    }

    func git(_ arguments: String..., directory: URL) async throws {
        let result = try await run(
            .path(FilePath("/usr/bin/git")),
            arguments: Arguments(arguments),
            workingDirectory: FilePath(directory.path),
            output: .discarded,
        )
        guard result.terminationStatus.isSuccess else {
            throw MoatError.commandFailed(["git"] + arguments, status: result.terminationStatus)
        }
    }
}
