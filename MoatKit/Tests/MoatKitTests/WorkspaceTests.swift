import Foundation
import Testing
@testable import MoatKit

struct WorkspaceTests {
    let fixture: Fixture

    init() throws {
        fixture = try Fixture()
    }

    @Test
    func resolvesSymlinks() throws {
        let link = fixture.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: fixture.workspace,
        )
        #expect(Workspace(folder: link).path == fixture.workspace.path)
    }

    @Test
    func nonexistentFolderIsStandardized() {
        let folder = URL(fileURLWithPath: "/nonexistent/a/../b")
        #expect(Workspace(folder: folder).path == "/nonexistent/b")
    }

    @Test
    func codesAsItsPath() throws {
        let workspace = Workspace(folder: fixture.workspace)
        let data = try JSONEncoder().encode([workspace])
        let decoder = JSONDecoder()
        #expect(try decoder.decode([String].self, from: data) == [workspace.path])
        #expect(try decoder.decode([Workspace].self, from: data) == [workspace])
    }

    @Test
    func decodingDoesNotResolve() throws {
        let data = Data(#"["/nonexistent/a/../b"]"#.utf8)
        let workspaces = try JSONDecoder().decode([Workspace].self, from: data)
        #expect(workspaces.map(\.path) == ["/nonexistent/a/../b"])
    }
}
