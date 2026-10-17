import Foundation
import Testing
@testable import MoatKit

@MainActor
struct SessionManagerTests {
    let fixture: Fixture

    init() throws {
        fixture = try Fixture()
    }

    /// A manager using the given commands.
    func sessionManager(
        checkSystem: [String] = ["/usr/bin/true"],
        startSystem: [String] = ["/usr/bin/false"],
        startVM: @escaping @Sendable (VMLaunchSpec) -> [String] = { _ in ["/usr/bin/true"] },
        stopVM: @escaping @Sendable (VMLaunchSpec) -> [String] = { _ in ["/usr/bin/false"] },
        listRunningVMs: [String] = ["/usr/bin/true"],
        listImages: [String] = ["/bin/echo", "[]"],
    ) -> SessionManager {
        let settingsManager = SettingsManager(
            environment: fixture.environment,
            hostCommands: HostCommands(
                checkSystem: checkSystem,
                startSystem: startSystem,
                startVM: startVM,
                stopVM: stopVM,
                listRunningVMs: listRunningVMs,
                listImages: listImages,
                gitPath: "/usr/bin/git",
            ),
        )
        return SessionManager(
            environment: fixture.environment,
            settingsManager: settingsManager,
        )
    }

    /// The metadata for the fixture's workspace.
    var metadata: SessionMetadata {
        SessionMetadata(workspace: workspace, name: "workspace")
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

    var workspace: Workspace {
        Workspace(folder: fixture.workspace)
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
        let metadata = SessionMetadata(
            workspace: Workspace(folder: URL(fileURLWithPath: "/\(name)")),
            name: name,
        )
        let hash = metadata.workspace.hash
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
        let workspace = Workspace(folder: URL(fileURLWithPath: "/projects/old"))
        let pointerFile = try fixture.write(
            workspace.path,
            path: "\(workspace.hash).pointer",
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
            startVM: { _ in ["/bin/sh", "-c", "echo started; read line"] },
        )
        let session = try await start(sessionManager)
        #expect(sessionManager.localSession(workspace: workspace) === session)
        try await waitForOutput("started", session: session)

        session.write(ArraySlice("\r".utf8))
        await session.waitForExit()
        #expect(session.state == .exited(code: 0))
    }

    @Test
    func startUsesOptionsAndClaudeArguments() async throws {
        // The VM command prints the parts of the spec it's given.
        let sessionManager = sessionManager(startVM: { spec in
            ["/bin/echo", spec.image, spec.memory] + spec.command
        })
        var options = SessionOptions()
        options.memory = "8G"
        options.image = "moat:swift"
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
        #expect(output.contains("moat:swift 8G claude"))
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
        let sessionManager = sessionManager(startVM: { _ in
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
        #expect(sessionManager.localSession(workspace: workspace) === second)
        await second.waitForExit()
    }

    @Test
    func stopStopsSession() async throws {
        let pidFile = fixture.root.appendingPathComponent("pid")
        let sessionManager = sessionManager(
            startVM: { _ in
                [
                    "/bin/sh",
                    "-c",
                    "echo $$ > '\(pidFile.path)'; echo ready; exec sleep 100",
                ]
            },
            stopVM: { _ in
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
            startVM: { spec in
                [
                    "/bin/sh",
                    "-c",
                    "echo $$ > '\(root)/\(spec.name).pid'; echo ready; "
                        + "exec sleep 100",
                ]
            },
            stopVM: { spec in
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
            workspace: Workspace(folder: other),
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
        let sessionManager = sessionManager(startVM: { _ in
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

    @Test
    func statusIsStoppedWhenNothingRuns() async throws {
        let sessionManager = sessionManager()
        try await sessionManager.refreshRunningVMs()
        #expect(sessionManager.status(metadata: metadata) == .stopped)
    }

    @Test
    func statusIsMissingWithoutWorkspace() {
        let missing = SessionMetadata(
            workspace: Workspace(folder: URL(fileURLWithPath: "/nonexistent")),
            name: "gone",
        )
        #expect(sessionManager().status(metadata: missing) == .missing)
    }

    @Test
    func statusIsRunningElsewhereWhenItsVMIsListed() async throws {
        let sessionManager = sessionManager(
            listRunningVMs: ["/bin/echo", "other-vm\n\(metadata.workspace.vmName)"],
        )
        try await sessionManager.refreshRunningVMs()
        #expect(sessionManager.status(metadata: metadata) == .runningElsewhere)
    }

    @Test
    func nothingRunsWhenSystemIsStopped() async throws {
        // Listing would fail, but isn't attempted.
        let sessionManager = sessionManager(
            checkSystem: ["/usr/bin/false"],
            listRunningVMs: ["/usr/bin/false"],
        )
        try await sessionManager.refreshRunningVMs()
        #expect(sessionManager.status(metadata: metadata) == .stopped)
    }

    @Test
    func refreshFailsIfListingFails() async throws {
        let sessionManager = sessionManager(listRunningVMs: ["/usr/bin/false"])
        await #expect(throws: MoatError.self) {
            try await sessionManager.refreshRunningVMs()
        }
    }

    @Test
    func moatImagesAreSortedAndFiltered() async throws {
        let json = """
        [
            {"configuration": {"name": "moat:swift"}, "id": "a"},
            {"configuration": {"name": "docker.io/library/debian:bookworm"}},
            {"configuration": {"name": "moat:base"}, "variants": []}
        ]
        """
        let sessionManager = sessionManager(listImages: ["/bin/echo", json])
        #expect(
            try await sessionManager.moatImages() == ["moat:base", "moat:swift"],
        )
    }

    @Test
    func noImagesWhenSystemIsStopped() async throws {
        // Listing would fail, but isn't attempted.
        let sessionManager = sessionManager(
            checkSystem: ["/usr/bin/false"],
            listImages: ["/usr/bin/false"],
        )
        #expect(try await sessionManager.moatImages() == [])
    }

    @Test
    func moatImagesFailsIfListingFails() async throws {
        let sessionManager = sessionManager(listImages: ["/usr/bin/false"])
        await #expect(throws: MoatError.self) {
            try await sessionManager.moatImages()
        }
    }

    @Test
    func startStartsSystemBeforeListing() async throws {
        // While the system is stopped, listing would fail.
        let marker = fixture.root.appendingPathComponent("system-started")
        let sessionManager = sessionManager(
            checkSystem: ["/bin/test", "-e", marker.path],
            startSystem: ["/usr/bin/touch", marker.path],
            listRunningVMs: ["/usr/bin/false"],
        )
        let session = try await start(sessionManager)
        await session.waitForExit()
        #expect(session.state == .exited(code: 0))
    }

    @Test
    func statusIsBusyThenIdle() async throws {
        let sessionManager = sessionManager(startVM: { _ in
            ["/bin/sh", "-c", "echo ready; read line"]
        })
        let session = try await start(sessionManager)
        try await waitForOutput("ready", session: session)

        #expect(sessionManager.status(metadata: metadata) == .busy)
        let later = Date().addingTimeInterval(4)
        #expect(sessionManager.status(metadata: metadata, date: later) == .idle)

        session.write(ArraySlice("\r".utf8))
        await session.waitForExit()
        #expect(sessionManager.status(metadata: metadata) == .stopped)
    }

    @Test
    func statusIsStoppedAfterExitUntilVMsAreListedAgain() async throws {
        // Lists the VMs named in a file; at first, none.
        let listFile = fixture.root.appendingPathComponent("running-vms")
        let sessionManager = sessionManager(
            startVM: { _ in ["/bin/sh", "-c", "echo ready; read line"] },
            listRunningVMs: [
                "/bin/sh",
                "-c",
                "cat '\(listFile.path)' 2>/dev/null; true",
            ],
        )
        let session = try await start(sessionManager)
        try await waitForOutput("ready", session: session)

        // Listed while it runs, the session's VM is its own.
        try fixture.write(workspace.vmName, path: listFile.lastPathComponent)
        try await sessionManager.refreshRunningVMs()
        session.write(ArraySlice("\r".utf8))
        await session.waitForExit()
        #expect(sessionManager.status(metadata: metadata) == .stopped)

        // Listed after it exits, the VM must have been started elsewhere.
        try await sessionManager.refreshRunningVMs()
        #expect(sessionManager.status(metadata: metadata) == .runningElsewhere)
    }

    @Test
    func startFailsIfRunningElsewhere() async throws {
        let sessionManager = sessionManager(
            listRunningVMs: ["/bin/echo", metadata.workspace.vmName],
        )
        await #expect(throws: MoatError.sessionRunningElsewhere(workspace)) {
            try await start(sessionManager)
        }
        #expect(sessionManager.localSession(workspace: workspace) == nil)
    }

    @Test
    func removeDeletesOnlyThatSessionsFiles() async throws {
        let sessionManager = sessionManager()
        let session = try await start(sessionManager)
        await session.waitForExit()
        let other = try writeMetadata(name: "other")
        let hash = workspace.hash
        #expect(Filesystem.isDirectory(sessions.appendingPathComponent(hash)))

        try await sessionManager.remove(session: metadata)
        let remaining = try FileManager.default
            .contentsOfDirectory(atPath: sessions.path)
        #expect(!remaining.contains { $0.hasPrefix(hash) })
        #expect(try sessionManager.list() == [other])
        #expect(sessionManager.localSession(workspace: workspace) == nil)
        #expect(Filesystem.isDirectory(fixture.workspace))
    }

    @Test
    func removeMissingSession() async throws {
        let missing = try writeMetadata(name: "gone")
        let sessionManager = sessionManager()
        try await sessionManager.remove(session: missing)
        #expect(try sessionManager.list().isEmpty)
    }

    @Test
    func removeRefusesRunningSession() async throws {
        let sessionManager = sessionManager(startVM: { _ in
            ["/bin/sh", "-c", "echo ready; read line"]
        })
        let session = try await start(sessionManager)
        try await waitForOutput("ready", session: session)

        await #expect(throws: MoatError.sessionRunning(workspace)) {
            try await sessionManager.remove(session: metadata)
        }
        #expect(try sessionManager.list().count == 1)

        session.write(ArraySlice("\r".utf8))
        await session.waitForExit()
    }

    @Test
    func removeRefusesSessionRunningElsewhere() async throws {
        let sessionManager = sessionManager(
            listRunningVMs: ["/bin/echo", metadata.workspace.vmName],
        )
        await #expect(throws: MoatError.sessionRunning(workspace)) {
            try await sessionManager.remove(session: metadata)
        }
    }
}
