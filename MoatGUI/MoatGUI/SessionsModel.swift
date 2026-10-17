import Foundation
import MoatKit
import Observation

/// A session recorded in `~/.moat/sessions`, with its latest status.
struct SessionDetails {
    let metadata: SessionMetadata
    let status: SessionStatus
}

// MARK: -

/// The sessions shown in the sidebar, and actions on them.
@Observable
final class SessionsModel {
    /// The latest session details.
    private(set) var sessionDetails: [SessionDetails] = []

    /// The workspace of the session selected in the sidebar.
    var selectedWorkspace: Workspace?

    @ObservationIgnored
    private let settingsManager: SettingsManager
    @ObservationIgnored
    private let sessionManager: SessionManager

    init(settingsManager: SettingsManager, sessionManager: SessionManager) {
        self.settingsManager = settingsManager
        self.sessionManager = sessionManager
    }

    // MARK: -

    /// Migrates sessions from earlier versions of moat, so they're listed.
    func migratePointers() {
        do {
            try sessionManager.migratePointers()
        } catch {
            Logger.error("Couldn't migrate .pointer files: \(error)")
        }
    }

    // MARK: -

    /// A full `Session` for the given workspace, if we own one.
    func localSession(workspace: Workspace) -> Session? {
        return sessionManager.localSession(workspace: workspace)
    }

    /// The names of all sessions that are running and owned by us.
    var localRunningSessionNames: [String] {
        return sessionDetails
            .filter { details in
                guard
                    let localSession = sessionManager.localSession(
                        workspace: details.metadata.workspace,
                    )
                else {
                    return false
                }

                switch localSession.state {
                case .running:
                    return true
                case .stopping, .exited, .signaled, .failed:
                    return false
                }
            }
            .map(\.metadata.name)
    }

    // MARK: -

    /// Re-reads the sessions from `~/.moat/sessions`.
    func reloadSessions() {
        do {
            sessionDetails = try sessionManager.list().map { metadata in
                SessionDetails(
                    metadata: metadata,
                    status: sessionManager.status(metadata: metadata),
                )
            }
            Logger.info("Listed \(sessionDetails.count) sessions")
        } catch {
            Logger.error("Couldn't list sessions: \(error)")
        }
    }

    /// Returns the status of the session for `workspace`.
    func status(workspace: Workspace) -> SessionStatus? {
        sessionDetails.first { $0.metadata.workspace == workspace }?.status
    }

    /// Regularly update session status.
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
    private func refreshRunningVMs() async {
        do {
            try await sessionManager.refreshRunningVMs()
        } catch {
            Logger.warn("Couldn't list running VMs: \(error)")
        }
        recomputeStatuses()
    }

    private func recomputeStatuses() {
        sessionDetails = sessionDetails.map { details in
            let metadata = details.metadata
            return SessionDetails(
                metadata: metadata,
                status: sessionManager.status(metadata: metadata),
            )
        }
    }

    // MARK: -

    /// The options each start begins with, from `settings.json`.
    var defaultOptions: SessionOptions {
        settingsManager.sessionOptions
    }

    /// Returns the paths of the skills in the host's `~/.claude/skills`,
    /// which every session gets.
    func hostSkills() -> [String] {
        do {
            return try GuestVM(environment: settingsManager.environment)
                .hostSkills()
                .map(\.path)
        } catch {
            Logger.warn("Couldn't list the host's skills: \(error)")
            return []
        }
    }

    /// Returns the name of the session for `workspace`, or the name a new one
    /// would get.
    func sessionName(workspace: Workspace) -> String {
        let details = sessionDetails.first { details in
            details.metadata.workspace == workspace
        }
        return details?.metadata.name ?? workspace.name
    }

    // MARK: -

    /// Selects the session for `workspace`, and starts it with `options`,
    /// unless it's already running.
    func start(workspace: Workspace, options: SessionOptions) {
        selectedWorkspace = workspace
        Task {
            await _start(workspace: workspace, options: options)
        }
    }

    private func _start(
        workspace: Workspace,
        options: SessionOptions,
    ) async {
        let session: Session
        do {
            session = try await sessionManager.start(
                workspace: workspace,
                options: options,
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

    // MARK: -

    /// Stops every running session, and waits for them to exit.
    func stopAll() async {
        do {
            try await sessionManager.stopAll()
        } catch {
            Logger.error("Couldn't stop every session: \(error)")
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

    // MARK: -

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
}
