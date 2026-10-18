import MoatKit
import SwiftUI

/// Edits the options new sessions start with, saving each change.
struct SessionDefaultsView: View {
    /// The skills in the host's `~/.claude/skills`, which every session gets.
    let hostSkills: [String]
    /// Available VM images.
    let images: [String]
    /// Asks for an environment file, returning its path, or nil if the user
    /// cancels.
    let chooseEnvFile: () async -> String?
    /// Asks for skill folders, returning their paths.
    let chooseSkills: () async -> [String]
    /// Saves the options.
    let save: (SessionOptions) -> Void

    @State private var options: SessionOptions

    init(
        options: SessionOptions,
        hostSkills: [String],
        images: [String],
        chooseEnvFile: @escaping () async -> String?,
        chooseSkills: @escaping () async -> [String],
        save: @escaping (SessionOptions) -> Void,
    ) {
        self.hostSkills = hostSkills
        self.images = images
        self.chooseEnvFile = chooseEnvFile
        self.chooseSkills = chooseSkills
        self.save = save
        _options = State(initialValue: options)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("""
            Default options for starting a session, overridable when \
            actually starting a session.
            """)
            .foregroundStyle(.secondary)

            SessionOptionsView(
                options: $options,
                hostSkills: hostSkills,
                images: images,
                chooseEnvFile: chooseEnvFile,
                chooseSkills: chooseSkills,
            )
        }
        .padding(20)
        .frame(width: 600)
        .fixedSize()
        .onChange(of: options) {
            save(options)
        }
    }
}
