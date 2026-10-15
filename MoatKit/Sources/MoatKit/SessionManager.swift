import Foundation
import Observation

/// Manages moat's sessions, persisted in `~/.moat/sessions`.
@MainActor
@Observable
public final class SessionManager {
    public let environment: HostEnvironment

    /// The commands to run sessions' VMs.
    @ObservationIgnored
    private let commands: SessionCommands

    /// The sessions started by this manager, keyed by their VMs' names. A
    /// session stays here after it exits, until it's started again.
    public private(set) var sessions: [String: Session] = [:]

    public init(environment: HostEnvironment, commands: SessionCommands) {
        self.environment = environment
        self.commands = commands
    }

    /// Returns the metadata of every session in `~/.moat/sessions`, sorted
    /// by name.
    public func list() throws -> [SessionMetadata] {
        let sessionsDirectory = environment.sessionsDirectory
        guard Filesystem.isDirectory(sessionsDirectory) else {
            return []
        }
        let metadataFiles = try FileManager.default
            .contentsOfDirectory(
                at: sessionsDirectory,
                includingPropertiesForKeys: nil,
            )
            .filter { $0.lastPathComponent.hasSuffix(".metadata.json") }
        let sessions = try metadataFiles.map { metadataFile in
            try SessionMetadata.load(file: metadataFile)
        }
        return sessions.sorted { first, second in
            first.name.localizedStandardCompare(second.name) == .orderedAscending
        }
    }

    /// Returns this manager's session for `workspace` (a path, as in
    /// `SessionMetadata`), if it has started one.
    public func session(workspace: String) -> Session? {
        sessions.values.first { session in
            session.spec.workingDirectory == workspace
        }
    }

    /// Starts a session for `workspace` with `options` on a terminal of
    /// `size`, running `claude` with `claudeArguments` added. Fails if this
    /// manager's session for `workspace` is already running.
    public func start(
        workspace: String,
        options: SessionOptions,
        claudeArguments: [String],
        size: TerminalSize,
    ) async throws -> Session {
        let spec = try await GuestVM(environment: environment).prepare(
            workspace: workspace,
            options: options,
            claudeArguments: claudeArguments,
        )
        if let existing = sessions[spec.name] {
            switch existing.state {
            case .running, .stopping:
                throw MoatError.sessionAlreadyRunning(workspace)
            case .exited, .signaled, .failed:
                break
            }
        }

        let session = try Session.start(
            spec: spec,
            checkSystemCommand: commands.checkSystem,
            startSystemCommand: commands.startSystem,
            startCommand: commands.start(spec),
            size: size,
        )
        sessions[spec.name] = session
        return session
    }

    /// Stops the running session for `workspace`, and waits for it to exit.
    /// Does nothing if there isn't one.
    public func stop(workspace: String) async throws {
        guard let session = session(workspace: workspace) else {
            return
        }
        try await session.stop(command: commands.stop(session.spec))
    }
}
