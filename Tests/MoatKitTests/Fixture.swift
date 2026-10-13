import Foundation
@testable import MoatKit

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

    var environment: MoatEnvironment {
        MoatEnvironment(homeDirectory: home)
    }

    func moat() -> Moat {
        Moat(environment: environment)
    }

    var options: SessionOptions {
        SessionOptions(workspace: workspace.path)
    }

    @discardableResult
    func makeDirectory(_ path: String, in base: URL? = nil) throws -> URL {
        let url = (base ?? root).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func write(_ contents: String, to path: String, in base: URL? = nil) throws -> URL {
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

    func git(_ arguments: String..., in directory: URL) throws {
        let status = try run(["git"] + arguments, in: directory)
        guard status == 0 else {
            throw MoatError.commandFailed(["git"] + arguments, status: status)
        }
    }
}
