import MoatKit
import SwiftUI

/// Asks how to start the session named `name` for `workspace`, with options
/// prefilled from `settings.json`.
struct StartSessionOptionsView: View {
    let name: String
    let workspace: Workspace
    /// The skills in the host's `~/.claude/skills`, which every session gets.
    let hostSkills: [String]
    /// Available VM images.
    let images: [String]
    /// Asks for an environment file, returning its path, or nil if the user
    /// cancels.
    let chooseEnvFile: () async -> String?
    /// Asks for skill folders, returning their paths.
    let chooseSkills: () async -> [String]
    /// Called with the chosen options when the user starts the session, or
    /// with nil if cancelled.
    let finish: (SessionOptions?) -> Void

    @State private var options: SessionOptions

    init(
        name: String,
        workspace: Workspace,
        options: SessionOptions,
        hostSkills: [String],
        images: [String],
        chooseEnvFile: @escaping () async -> String?,
        chooseSkills: @escaping () async -> [String],
        finish: @escaping (SessionOptions?) -> Void,
    ) {
        self.name = name
        self.workspace = workspace
        self.hostSkills = hostSkills
        self.images = images
        self.chooseEnvFile = chooseEnvFile
        self.chooseSkills = chooseSkills
        self.finish = finish
        _options = State(initialValue: options)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Run Claude in \"\(name)\"?")
                    .font(.title3.weight(.semibold))
                Text(workspace.path)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            SessionOptionsView(
                options: $options,
                hostSkills: hostSkills,
                images: images,
                chooseEnvFile: chooseEnvFile,
                chooseSkills: chooseSkills,
            )

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    finish(nil)
                }
                .keyboardShortcut(.cancelAction)
                Button("Start") {
                    finish(options)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 600)
        .fixedSize()
    }
}
