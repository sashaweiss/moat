import Foundation
import MoatKit
import Observation

/// The sessions shown in the sidebar, and actions on them.
@Observable
final class SessionsModel {
    /// The sessions recorded in `~/.moat/sessions`.
    private(set) var sessions: [SessionMetadata] = []

    /// The workspace of the session selected in the sidebar.
    var selectedWorkspace: Workspace?

    /// Each session's status, by workspace, as of `updateStatuses()`.
    private(set) var statuses: [Workspace: SessionStatus] = [:]

    @ObservationIgnored
    private let settingsManager: SettingsManager
    @ObservationIgnored
    private let sessionManager: SessionManager

    init(settingsManager: SettingsManager, sessionManager: SessionManager) {
        self.settingsManager = settingsManager
        self.sessionManager = sessionManager
    }

    /// Migrates sessions from earlier versions of moat, so they're listed.
    func migratePointers() {
        do {
            try sessionManager.migratePointers()
        } catch {
            Logger.error("Couldn't migrate .pointer files: \(error)")
        }
    }

    /// Re-reads the sessions from `~/.moat/sessions`.
    func reloadSessions() {
        do {
            sessions = try sessionManager.list()
            Logger.info("Listed \(sessions.count) sessions")
        } catch {
            Logger.error("Couldn't list sessions: \(error)")
        }
    }

    /// Returns the status of the session for `workspace`.
    func status(workspace: Workspace) -> SessionStatus {
        statuses[workspace] ?? .stopped
    }

    /// Keeps `statuses` up to date until cancelled: updates them every
    /// second, and refreshes which VMs are running every 5 seconds.
    func updateStatuses() async {
        var seconds = 5
        while !Task.isCancelled {
            if seconds == 5 {
                seconds = 0
                await refreshRunningVMs()
            } else {
                recomputeStatuses()
            }
            seconds += 1
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Refreshes which VMs are running (e.g., started by MoatCLI), and the
    /// statuses that depend on it.
    func refreshRunningVMs() async {
        do {
            try await sessionManager.refreshRunningVMs()
        } catch {
            Logger.warn("Couldn't list running VMs: \(error)")
        }
        recomputeStatuses()
    }

    private func recomputeStatuses() {
        var statuses: [Workspace: SessionStatus] = [:]
        for session in sessions {
            statuses[session.workspace] = sessionManager.status(
                session: session,
            )
        }
        self.statuses = statuses
    }

    /// Returns the session started for `workspace`, if there is one.
    func session(workspace: Workspace) -> Session? {
        sessionManager.session(workspace: workspace)
    }

    /// Adds a session for `folder`, as `start(workspace:)` does.
    func add(folder: URL) {
        start(workspace: Workspace(folder: folder))
    }

    /// Selects the session for `workspace`, and starts it with the default
    /// options, unless it's already running.
    func start(workspace: Workspace) {
        selectedWorkspace = workspace
        Task {
            await _start(workspace: workspace)
        }
    }

    private func _start(workspace: Workspace) async {
        let session: Session
        do {
            session = try await sessionManager.start(
                workspace: workspace,
                options: try settingsManager.loadSettings(),
                claudeArguments: [],
                // The terminal showing the session resizes it to fit.
                size: TerminalSize(columns: 80, rows: 24),
            )
        } catch MoatError.sessionAlreadyRunning,
            MoatError.sessionRunningElsewhere
        {
            // It's already running, and selected; that's all there is to do.
            return
        } catch {
            Logger.error("Couldn't start session for \(workspace): \(error)")
            return
        }
        Logger.info("Started session for \(workspace)")
        // A new session has just been recorded, so list it.
        reloadSessions()

        await session.waitForExit()
        switch session.state {
        case .exited(let code):
            Logger.info("Session for \(workspace) exited with code \(code)")
        case .signaled(let signal):
            Logger.info(
                "Session for \(workspace) was killed by signal \(signal)",
            )
        case .failed(let description):
            Logger.error("Session for \(workspace) failed: \(description)")
        case .running, .stopping:
            Logger.error(
                "Session for \(workspace) was still running after waiting",
            )
        }
    }

    /// Stops the session for `workspace`, if it's running.
    func stop(workspace: Workspace) {
        Task {
            await _stop(workspace: workspace)
        }
    }

    private func _stop(workspace: Workspace) async {
        do {
            try await sessionManager.stop(workspace: workspace)
        } catch {
            Logger.error("Couldn't stop session for \(workspace): \(error)")
        }
    }

    /// Removes the session for `session`, deleting everything moat has for
    /// it, including Claude's history.
    func remove(session: SessionMetadata) {
        Task {
            await _remove(session: session)
        }
    }

    private func _remove(session: SessionMetadata) async {
        do {
            try await sessionManager.remove(session: session)
        } catch {
            Logger.error(
                "Couldn't remove session for \(session.workspace): \(error)",
            )
            return
        }
        Logger.info("Removed session for \(session.workspace)")
        if selectedWorkspace == session.workspace {
            selectedWorkspace = nil
        }
        reloadSessions()
    }

    /// The names of the sessions that are running.
    var runningSessionNames: [String] {
        sessions
            .filter { metadata in
                let session = sessionManager.session(workspace: metadata.workspace)
                switch session?.state {
                case .running, .stopping:
                    return true
                case .exited, .signaled, .failed, nil:
                    return false
                }
            }
            .map(\.name)
    }

    /// Stops every running session, and waits for them to exit.
    func stopAll() async {
        do {
            try await sessionManager.stopAll()
        } catch {
            Logger.error("Couldn't stop every session: \(error)")
        }
    }
}
