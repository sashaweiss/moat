import Foundation
import Testing
@testable import MoatKit

@MainActor
struct SessionManagerTests {
    let fixture: Fixture

    init() throws {
        fixture = try Fixture()
    }

    /// A manager whose sessions run `start` and `stop` as their VM commands,
    /// with `checkSystem` and `startSystem` for the system.
    func sessionManager(
        checkSystem: [String] = ["/usr/bin/true"],
        startSystem: [String] = ["/usr/bin/false"],
        start: @escaping @Sendable (VMLaunchSpec) -> [String] = { _ in ["/usr/bin/true"] },
        stop: @escaping @Sendable (VMLaunchSpec) -> [String] = { _ in ["/usr/bin/false"] },
    ) -> SessionManager {
        SessionManager(
            environment: fixture.environment,
            commands: SessionCommands(
                checkSystem: checkSystem,
                startSystem: startSystem,
                start: start,
                stop: stop,
            ),
        )
    }

    /// Starts `sessionManager`'s session for the fixture's workspace.
    func start(
        _ sessionManager: SessionManager,
        options: SessionOptions = SessionOptions(),
        claudeArguments: [String] = [],
    ) async throws -> Session {
        try await sessionManager.start(
            workspace: workspace,
            options: options,
            claudeArguments: claudeArguments,
            size: TerminalSize(columns: 80, rows: 24),
        )
    }

    var workspace: String {
        fixture.workspace.path
    }

    /// Reads `session`'s output until it contains `text`.
    func waitForOutput(_ text: String, session: Session) async throws {
        var output: [UInt8] = []
        for try await chunk in session.outputStream {
            output += chunk
            if String(decoding: output, as: UTF8.self).contains(text) {
                return
            }
        }
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
        #expect(try sessionManager().list().isEmpty)
    }

    // Sorting ignores case, as Finder does, so "Gamma" comes last.
    @Test
    func listIsSortedByName() throws {
        let beta = try writeMetadata(name: "beta")
        let gamma = try writeMetadata(name: "Gamma")
        let alpha = try writeMetadata(name: "alpha")
        #expect(try sessionManager().list() == [alpha, beta, gamma])
    }

    @Test
    func listIgnoresOtherSessionFiles() throws {
        let metadata = try writeMetadata(name: "workspace")
        try fixture.write("{}", path: "abc.claude.json", base: sessions)
        try fixture.write("", path: "abc.CLAUDE.md", base: sessions)
        try fixture.write("/old", path: "abc.pointer", base: sessions)
        try fixture.makeDirectory("abc", base: sessions)
        #expect(try sessionManager().list() == [metadata])
    }

    @Test
    func migratePointers() throws {
        let workspace = "/projects/old"
        let hash = GuestVM.hash(workspace: URL(fileURLWithPath: workspace))
        let pointerFile = try fixture.write(
            workspace,
            path: "\(hash).pointer",
            base: sessions,
        )
        let sessionManager = sessionManager()
        try sessionManager.migratePointers()
        #expect(try sessionManager.list() == [
            SessionMetadata(workspace: workspace, name: "old"),
        ])
        #expect(!FileManager.default.fileExists(atPath: pointerFile.path))
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
            try sessionManager().list()
        }
    }

    @Test
    func startRunsSession() async throws {
        let sessionManager = sessionManager(
            start: { _ in ["/bin/sh", "-c", "echo started; read line"] },
        )
        let session = try await start(sessionManager)
        #expect(sessionManager.sessions[session.spec.name] === session)
        #expect(sessionManager.session(workspace: workspace) === session)
        try await waitForOutput("started", session: session)

        session.write(ArraySlice("\r".utf8))
        await session.waitForExit()
        #expect(session.state == .exited(code: 0))
    }

    @Test
    func startUsesOptionsAndClaudeArguments() async throws {
        // The VM command prints the parts of the spec it's given.
        let sessionManager = sessionManager(start: { spec in
            ["/bin/echo", spec.memory] + spec.command
        })
        var options = SessionOptions()
        options.memory = "8G"
        let session = try await start(
            sessionManager,
            options: options,
            claudeArguments: ["--resume"],
        )

        var outputBytes: [UInt8] = []
        for try await chunk in session.outputStream {
            outputBytes += chunk
        }
        let output = String(decoding: outputBytes, as: UTF8.self)
        #expect(output.contains("8G claude"))
        #expect(output.contains("--resume"))
    }

    @Test
    func startStartsSystemIfNeeded() async throws {
        let marker = fixture.root.appendingPathComponent("system-started")
        let sessionManager = sessionManager(
            checkSystem: ["/usr/bin/false"],
            startSystem: ["/usr/bin/touch", marker.path],
        )
        let session = try await start(sessionManager)
        await session.waitForExit()
        #expect(Filesystem.isFile(marker))
    }

    @Test
    func sessionFailsIfSystemDoesNotStart() async throws {
        let sessionManager = sessionManager(
            checkSystem: ["/usr/bin/false"],
            startSystem: ["/usr/bin/false"],
        )
        let session = try await start(sessionManager)
        await session.waitForExit()
        switch session.state {
        case .failed:
            break
        case .running, .stopping, .exited, .signaled:
            Issue.record("Unexpected state: \(session.state)")
        }
    }

    @Test
    func startFailsIfAlreadyRunning() async throws {
        let sessionManager = sessionManager(start: { _ in
            ["/bin/sh", "-c", "read line"]
        })
        let session = try await start(sessionManager)
        await #expect(throws: MoatError.sessionAlreadyRunning(workspace)) {
            try await start(sessionManager)
        }

        session.write(ArraySlice("\r".utf8))
        await session.waitForExit()
    }

    @Test
    func startAgainAfterExit() async throws {
        let sessionManager = sessionManager()
        let first = try await start(sessionManager)
        await first.waitForExit()

        let second = try await start(sessionManager)
        #expect(second !== first)
        #expect(sessionManager.session(workspace: workspace) === second)
        await second.waitForExit()
    }

    @Test
    func stopStopsSession() async throws {
        let pidFile = fixture.root.appendingPathComponent("pid")
        let sessionManager = sessionManager(
            start: { _ in
                [
                    "/bin/sh",
                    "-c",
                    "echo $$ > '\(pidFile.path)'; echo ready; exec sleep 100",
                ]
            },
            stop: { _ in
                ["/bin/sh", "-c", "kill -TERM $(cat '\(pidFile.path)')"]
            },
        )
        let session = try await start(sessionManager)
        try await waitForOutput("ready", session: session)

        try await sessionManager.stop(workspace: workspace)
        #expect(session.state == .signaled(signal: SIGTERM))
    }

    /// A manager whose sessions each record their PID in a file named after
    /// their VM, and whose stop command sends that PID SIGTERM.
    func killableSessionManager() -> SessionManager {
        let root = fixture.root.path
        return sessionManager(
            start: { spec in
                [
                    "/bin/sh",
                    "-c",
                    "echo $$ > '\(root)/\(spec.name).pid'; echo ready; "
                        + "exec sleep 100",
                ]
            },
            stop: { spec in
                [
                    "/bin/sh",
                    "-c",
                    "kill -TERM $(cat '\(root)/\(spec.name).pid')",
                ]
            },
        )
    }

    @Test
    func stopAllStopsEverySession() async throws {
        let sessionManager = killableSessionManager()
        let other = try fixture.makeDirectory("other")
        let first = try await start(sessionManager)
        let second = try await sessionManager.start(
            workspace: other.path,
            options: SessionOptions(),
            claudeArguments: [],
            size: TerminalSize(columns: 80, rows: 24),
        )
        try await waitForOutput("ready", session: first)
        try await waitForOutput("ready", session: second)
        #expect(sessionManager.runningSessions.count == 2)

        try await sessionManager.stopAll()
        #expect(first.state == .signaled(signal: SIGTERM))
        #expect(second.state == .signaled(signal: SIGTERM))
        #expect(sessionManager.runningSessions.isEmpty)
    }

    @Test
    func stopAllWithoutSessions() async throws {
        try await sessionManager().stopAll()
    }

    @Test
    func stopAllThrowsIfStoppingFails() async throws {
        // The default stop command fails.
        let sessionManager = sessionManager(start: { _ in
            ["/bin/sh", "-c", "echo ready; read line"]
        })
        let session = try await start(sessionManager)
        try await waitForOutput("ready", session: session)

        await #expect(throws: MoatError.self) {
            try await sessionManager.stopAll()
        }
        #expect(sessionManager.runningSessions.count == 1)

        session.write(ArraySlice("\r".utf8))
        await session.waitForExit()
    }
}
