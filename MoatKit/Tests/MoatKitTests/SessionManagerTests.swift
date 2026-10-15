import Foundation
import Testing
@testable import MoatKit

@MainActor
struct SessionManagerTests {
    let fixture: Fixture
    let sessionManager: SessionManager

    init() throws {
        fixture = try Fixture()
        sessionManager = SessionManager(environment: fixture.environment)
    }

    var sessions: URL {
        fixture.home.appendingPathComponent(".moat/sessions")
    }

    /// Writes metadata for a session named `name`, with workspace `/<name>`.
    @discardableResult
    func writeMetadata(name: String) throws -> SessionMetadata {
        try fixture.makeDirectory(".moat/sessions", base: fixture.home)
        let metadata = SessionMetadata(workspace: "/\(name)", name: name)
        let hash = GuestVM.hash(workspace: URL(fileURLWithPath: "/\(name)"))
        try metadata.write(
            file: fixture.environment.metadataFile(workspaceHash: hash),
        )
        return metadata
    }

    @Test
    func listWithoutSessionsDirectoryIsEmpty() throws {
        #expect(try sessionManager.list().isEmpty)
    }

    // Sorting ignores case, as Finder does, so "Gamma" comes last.
    @Test
    func listIsSortedByName() throws {
        let beta = try writeMetadata(name: "beta")
        let gamma = try writeMetadata(name: "Gamma")
        let alpha = try writeMetadata(name: "alpha")
        #expect(try sessionManager.list() == [alpha, beta, gamma])
    }

    @Test
    func listIgnoresOtherSessionFiles() throws {
        let metadata = try writeMetadata(name: "workspace")
        try fixture.write("{}", path: "abc.claude.json", base: sessions)
        try fixture.write("", path: "abc.CLAUDE.md", base: sessions)
        try fixture.write("/old", path: "abc.pointer", base: sessions)
        try fixture.makeDirectory("abc", base: sessions)
        #expect(try sessionManager.list() == [metadata])
    }

    @Test
    func listFailsOnInvalidMetadata() throws {
        try writeMetadata(name: "workspace")
        let invalid = try fixture.write(
            "{",
            path: "abc.metadata.json",
            base: sessions,
        )
        #expect(throws: MoatError.invalidMetadataFile(invalid.path)) {
            try sessionManager.list()
        }
    }
}
