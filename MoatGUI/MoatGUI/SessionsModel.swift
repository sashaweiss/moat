import Foundation
import MoatKit
import Observation

/// The sessions shown in the sidebar, and actions on them.
@Observable
final class SessionsModel {
    /// The sessions recorded in `~/.moat/sessions`.
    private(set) var sessions: [SessionMetadata] = []

    /// The workspace of the session selected in the sidebar.
    var selectedWorkspace: String?

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

    /// Starts the session for `workspace`, with the default options.
    func start(workspace: String) {
        Task {
            await _start(workspace: workspace)
        }
    }

    /// Stops the session for `workspace`, if it's running.
    func stop(workspace: String) {
        Task {
            await _stop(workspace: workspace)
        }
    }

    private func _start(workspace: String) async {
        let session: Session
        do {
            session = try await sessionManager.start(
                workspace: workspace,
                options: try settingsManager.loadSettings(),
                claudeArguments: [],
                // A placeholder until there's a terminal view to size it.
                size: TerminalSize(columns: 80, rows: 24),
            )
        } catch {
            Logger.error("Couldn't start session for \(workspace): \(error)")
            return
        }
        Logger.info("Started session for \(workspace)")

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

    private func _stop(workspace: String) async {
        do {
            try await sessionManager.stop(workspace: workspace)
        } catch {
            Logger.error("Couldn't stop session for \(workspace): \(error)")
        }
    }
}
