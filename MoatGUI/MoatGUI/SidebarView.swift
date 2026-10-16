import MoatKit
import SwiftUI

/// The sidebar: the sessions in `model`, each with its workspace and status.
struct SidebarView: View {
    @Bindable var model: SessionsModel
    /// Asks for options to start the session for a workspace, and starts it.
    let startSession: (Workspace) -> Void
    /// Confirms removing a session, and removes it.
    let removeSession: (SessionMetadata) -> Void

    var body: some View {
        List(
            model.sessions,
            id: \.workspace,
            selection: $model.selectedWorkspace,
        ) { session in
            let status = model.status(workspace: session.workspace)
            SessionRow(session: session, status: status)
                .contextMenu {
                    Button("Start…") {
                        startSession(session.workspace)
                    }
                    .disabled(!canStart(status: status))
                    Button("Stop") {
                        model.stop(workspace: session.workspace)
                    }
                    .disabled(!canStop(status: status))
                    Divider()
                    Button("Remove…") {
                        removeSession(session)
                    }
                    .disabled(!canRemove(status: status))
                }
        }
        .listStyle(.sidebar)
    }

    private func canStart(status: SessionStatus) -> Bool {
        switch status {
        case .stopped:
            true
        case .idle, .busy, .runningElsewhere, .missing:
            false
        }
    }

    private func canRemove(status: SessionStatus) -> Bool {
        switch status {
        case .stopped, .missing:
            true
        case .idle, .busy, .runningElsewhere:
            false
        }
    }

    private func canStop(status: SessionStatus) -> Bool {
        switch status {
        case .idle, .busy:
            true
        case .stopped, .runningElsewhere, .missing:
            false
        }
    }
}

/// A session's status badge and name, with its workspace beneath. Sessions
/// that can't be used here are dimmed, and say why.
private struct SessionRow: View {
    let session: SessionMetadata
    let status: SessionStatus

    var body: some View {
        HStack {
            Circle()
                .fill(badgeColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading) {
                Text(session.name)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .opacity(isDimmed ? 0.5 : 1)
    }

    private var badgeColor: Color {
        switch status {
        case .stopped:
            .gray
        case .missing:
            .black
        case .idle:
            .green
        case .busy:
            .orange
        case .runningElsewhere:
            .blue
        }
    }

    /// The workspace, and why the session can't be used here, if it can't.
    private var caption: String {
        switch status {
        case .stopped, .idle, .busy:
            session.workspace.path
        case .runningElsewhere:
            "Running elsewhere: \(session.workspace)"
        case .missing:
            "Missing: \(session.workspace)"
        }
    }

    private var isDimmed: Bool {
        switch status {
        case .stopped, .idle, .busy:
            false
        case .runningElsewhere, .missing:
            true
        }
    }
}
