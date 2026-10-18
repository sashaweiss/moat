import MoatKit
import SwiftUI

/// Edits where moat finds its tools, saving each change.
struct ToolLocationsView: View {
    /// Asks for the executable named by the first argument, starting near
    /// the path in the second, and returns its path, or nil if the user
    /// cancels.
    let chooseExecutable: (String, String) async -> String?
    /// Saves the settings.
    let save: (HostSettings) -> Void

    @State private var hostSettings: HostSettings

    init(
        hostSettings: HostSettings,
        chooseExecutable: @escaping (String, String) async -> String?,
        save: @escaping (HostSettings) -> Void,
    ) {
        self.chooseExecutable = chooseExecutable
        self.save = save
        _hostSettings = State(initialValue: hostSettings)
    }

    var body: some View {
        Grid(alignment: .leading, verticalSpacing: 12) {
            GridRow(alignment: .firstTextBaseline) {
                Text("container:")
                    .gridColumnAlignment(.trailing)
                toolField(name: "container", path: $hostSettings.containerPath)
            }
            GridRow(alignment: .firstTextBaseline) {
                Text("git:")
                toolField(name: "git", path: $hostSettings.gitPath)
            }
        }
        .padding(20)
        .frame(width: 600)
        .fixedSize()
        .onChange(of: hostSettings) {
            save(hostSettings)
        }
    }

    /// A field for the path of the `name` executable, with a button to
    /// choose it, and a warning if there's no executable at the path.
    private func toolField(name: String, path: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(name, text: path)
                    .labelsHidden()
                Button("Choose…") {
                    Task {
                        let chosen = await chooseExecutable(
                            name,
                            path.wrappedValue,
                        )
                        if let chosen {
                            path.wrappedValue = chosen
                        }
                    }
                }
            }
            if !FileManager.default.isExecutableFile(atPath: path.wrappedValue) {
                // Tighter than a `Label`'s spacing between icon and text.
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("There's no executable at this path.")
                }
                .font(.callout)
                .foregroundStyle(.orange)
            }
        }
    }
}
