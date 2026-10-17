import Foundation
import Observation
import Subprocess

/// A session's status, as shown to the user.
public enum SessionStatus: Hashable, Sendable {
    /// Not running.
    case stopped
    /// Running here, and the VM hasn't written to its terminal lately.
    case idle
    /// Running here, and the VM has written to its terminal lately (e.g.,
    /// Claude is working).
    case busy
    /// Running, but not started here (e.g., by MoatCLI).
    case runningElsewhere
    /// The session's workspace no longer exists.
    case missing
}

/// Manages moat's sessions, persisted in `~/.moat/sessions`.
@MainActor
@Observable
public final class SessionManager {
    public let environment: HostEnvironment

    @ObservationIgnored
    private let settingsManager: SettingsManager

    private var commands: HostCommands {
        settingsManager.hostCommands
    }

    /// The sessions started by this manager, keyed by their VMs' names. A
    /// session stays here after it exits, until it's started again.
    private var localSessions: [String: Session] = [:]

    /// The running VMs, including those not started here (and which this
    /// manager therefore has no session for), as of a point in time.
    private struct RunningVMsSnapshot {
        let names: Set<String>
        /// When this snapshot was taken.
        let date: Date
    }

    /// The running VMs, as of `refreshRunningVMs()`.
    private var runningVMsSnapshot = RunningVMsSnapshot(
        names: [],
        date: .distantPast,
    )

    /// How recently a session's VM must have written to its terminal for the
    /// session to be busy.
    private static let busyInterval: TimeInterval = 3

    public init(
        environment: HostEnvironment,
        settingsManager: SettingsManager,
    ) {
        self.environment = environment
        self.settingsManager = settingsManager
    }

    /// Migrates every session in `~/.moat/sessions` that has only a
    /// `.pointer` file, from earlier versions of moat, so `list()` includes
    /// it.
    public func migratePointers() throws {
        let sessionsDirectory = environment.sessionsDirectory
        guard Filesystem.isDirectory(sessionsDirectory) else {
            return
        }
        let guestVM = GuestVM(environment: environment)
        let pointerFiles = try FileManager.default
            .contentsOfDirectory(
                at: sessionsDirectory,
                includingPropertiesForKeys: nil,
            )
            .filter { $0.pathExtension == "pointer" }
        for pointerFile in pointerFiles {
            try guestVM.migratePointer(file: pointerFile)
        }
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

    /// Returns this manager's session for `workspace`, if it has started one.
    public func localSession(workspace: Workspace) -> Session? {
        localSessions[workspace.vmName]
    }

    /// Starts a session for `workspace` with `options` on a terminal of
    /// `size`, running `claude` with `claudeArguments` added. Fails if the
    /// session is already running, here or elsewhere.
    public func start(
        workspace: Workspace,
        options: SessionOptions,
        claudeArguments: [String],
        size: TerminalSize,
    ) async throws -> Session {
        let spec = try await GuestVM(environment: environment).prepare(
            workspace: workspace,
            options: options,
            claudeArguments: claudeArguments,
            gitPath: commands.gitPath,
        )
        if let existing = localSessions[spec.name] {
            switch existing.state {
            case .running, .stopping:
                throw MoatError.sessionAlreadyRunning(workspace)
            case .exited, .signaled, .failed:
                break
            }
        }

        try await refreshRunningVMs()
        guard !runningVMsSnapshot.names.contains(spec.name) else {
            throw MoatError.sessionRunningElsewhere(workspace)
        }

        let session = try Session.start(
            spec: spec,
            checkSystemCommand: commands.checkSystem,
            startSystemCommand: commands.startSystem,
            startCommand: commands.startVM(spec),
            size: size,
        )
        localSessions[spec.name] = session
        return session
    }

    /// Stops the running session for `workspace`, and waits for it to exit.
    /// Does nothing if there isn't one.
    public func stop(workspace: Workspace) async throws {
        guard let session = localSession(workspace: workspace) else {
            return
        }
        try await session.stop(command: commands.stopVM(session.spec))
    }

    /// Removes `session` (which must be stopped or missing) from
    /// `~/.moat/sessions`, deleting everything moat has recorded for it,
    /// including Claude's history. Doesn't touch its workspace.
    public func remove(session metadata: SessionMetadata) async throws {
        try await refreshRunningVMs()
        switch status(metadata: metadata) {
        case .stopped, .missing:
            break
        case .idle, .busy, .runningElsewhere:
            throw MoatError.sessionRunning(metadata.workspace)
        }

        // A session's files are all named for its workspace's hash.
        let hash = metadata.workspace.hash
        let sessionFiles = try FileManager.default
            .contentsOfDirectory(
                at: environment.sessionsDirectory,
                includingPropertiesForKeys: nil,
            )
            .filter { file in
                let name = file.lastPathComponent
                return name == hash || name.hasPrefix("\(hash).")
            }
        for file in sessionFiles {
            try FileManager.default.removeItem(at: file)
        }
        localSessions[metadata.workspace.vmName] = nil
    }

    /// This manager's sessions that are running (or stopping).
    public var runningSessions: [Session] {
        localSessions.values.filter { session in
            switch session.state {
            case .running, .stopping:
                true
            case .exited, .signaled, .failed:
                false
            }
        }
    }

    /// Stops every running session at once, and waits for them to exit. If
    /// any fail to stop, still stops the rest, then throws the first failure.
    public func stopAll() async throws {
        let errors = await withTaskGroup(of: (any Error)?.self) { group in
            for session in runningSessions {
                let command = commands.stopVM(session.spec)
                group.addTask {
                    do {
                        try await session.stop(command: command)
                        return nil
                    } catch {
                        return error
                    }
                }
            }
            var errors: [any Error] = []
            for await error in group {
                if let error {
                    errors.append(error)
                }
            }
            return errors
        }
        if let error = errors.first {
            throw error
        }
    }

    /// Returns the latest-known status of the session with the given `metadata`
    /// at `date`.
    public func status(
        metadata: SessionMetadata,
        date: Date = Date(),
    ) -> SessionStatus {
        guard Filesystem.isDirectory(metadata.workspace.url) else {
            return .missing
        }

        if let session = localSession(workspace: metadata.workspace) {
            switch session.state {
            case .running, .stopping:
                if
                    let lastOutputDate = session.lastOutputDate,
                    date.timeIntervalSince(lastOutputDate) < Self.busyInterval
                {
                    return .busy
                }

                return .idle
            case .exited, .signaled, .failed:
                // VMs listed before the session exited include its own, so
                // they don't show whether it's been started elsewhere since.
                if
                    let exitDate = session.exitDate,
                    runningVMsSnapshot.date < exitDate
                {
                    return .stopped
                }
            }
        }

        if runningVMsSnapshot.names.contains(metadata.workspace.vmName) {
            return .runningElsewhere
        }

        return .stopped
    }

    /// Whether the tool's system, which runs VMs, is running.
    private func isSystemRunning() async throws -> Bool {
        try await Subprocess.run(
            .moatCommand(commands.checkSystem),
            output: .discarded,
        ).terminationStatus.isSuccess
    }

    /// Re-lists the running VMs, for `status(metadata:date:)`. If the tool's
    /// system isn't running, no VMs are.
    public func refreshRunningVMs() async throws {
        // Taken before listing, so VMs that stop while listing count as
        // running as of this date.
        let date = Date()
        guard try await isSystemRunning() else {
            runningVMsSnapshot = RunningVMsSnapshot(names: [], date: date)
            return
        }

        let result = try await Subprocess.run(
            .moatCommand(commands.listRunningVMs),
            output: .string(limit: 1 << 20),
        )
        guard result.terminationStatus.isSuccess else {
            throw MoatError.commandFailed(
                commands.listRunningVMs,
                status: result.terminationStatus,
            )
        }

        runningVMsSnapshot = RunningVMsSnapshot(
            names: Set(
                result.standardOutput
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty },
            ),
            date: date,
        )
    }

    /// An image, as `listImages` prints it.
    private struct ListedImage: Decodable {
        struct Configuration: Decodable {
            let name: String
        }

        let configuration: Configuration
    }

    /// Returns the names of moat's images (those in the `moat` repository,
    /// like `moat:base`), sorted. If the tool's system isn't running, there
    /// are none.
    public func moatImages() async throws -> [String] {
        guard try await isSystemRunning() else {
            return []
        }

        let result = try await Subprocess.run(
            .moatCommand(commands.listImages),
            output: .data(limit: 1 << 24),
        )
        guard result.terminationStatus.isSuccess else {
            throw MoatError.commandFailed(
                commands.listImages,
                status: result.terminationStatus,
            )
        }

        return try JSONDecoder()
            .decode([ListedImage].self, from: result.standardOutput)
            .map(\.configuration.name)
            .filter { $0.hasPrefix("moat:") }
            .sorted { first, second in
                first.localizedStandardCompare(second) == .orderedAscending
            }
    }
}
