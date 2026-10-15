import MoatKit
import SwiftUI

/// The sidebar: the sessions in `model`, each with its workspace.
struct SidebarView: View {
    @Bindable var model: SessionsModel

    var body: some View {
        List(
            model.sessions,
            id: \.workspace,
            selection: $model.selectedWorkspace,
        ) { session in
            SessionRow(session: session)
                .contextMenu {
                    Button("Start") {
                        model.start(workspace: session.workspace)
                    }
                    Button("Stop") {
                        model.stop(workspace: session.workspace)
                    }
                }
        }
        .listStyle(.sidebar)
    }
}

/// A session's name, with its workspace beneath.
private struct SessionRow: View {
    let session: SessionMetadata

    var body: some View {
        VStack(alignment: .leading) {
            Text(session.name)
            Text(session.workspace)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
