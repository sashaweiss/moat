import MoatKit
import SwiftUI

/// Asks how to start the session named `name` for `workspace`, with options
/// prefilled from `settings.json`.
///
/// Options are split between General and Advanced tabs.
struct StartSessionOptionsView: View {
    private enum Tab {
        case general
        case advanced
    }

    /// Claude Code's permission modes.
    private static let claudePermissionModes = [
        "default",
        "acceptEdits",
        "plan",
        "auto",
        "dontAsk",
        "bypassPermissions",
    ]

    private static let labelWidth: CGFloat = 175
    private static let skillsVisibleRows = 3
    private static let skillsRowHeight: CGFloat = 24

    let name: String
    let workspace: Workspace
    /// The skills in the host's `~/.claude/skills`, which every session gets.
    let hostSkills: [String]
    /// Asks for an environment file, returning its path, or nil if the user
    /// cancels.
    let chooseEnvFile: () async -> String?
    /// Asks for skill folders, returning their paths.
    let chooseSkills: () async -> [String]
    /// Called with the chosen options when the user starts the session, or
    /// with nil if cancelled.
    let finish: (SessionOptions?) -> Void

    @State private var options: SessionOptions
    @State private var tab = Tab.general
    @State private var selectedSkills: Set<String> = []

    init(
        name: String,
        workspace: Workspace,
        options: SessionOptions,
        hostSkills: [String],
        chooseEnvFile: @escaping () async -> String?,
        chooseSkills: @escaping () async -> [String],
        finish: @escaping (SessionOptions?) -> Void,
    ) {
        self.name = name
        self.workspace = workspace
        self.hostSkills = hostSkills
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

            VStack(spacing: 8) {
                Picker("Options", selection: $tab) {
                    Text("General").tag(Tab.general)
                    Text("Advanced").tag(Tab.advanced)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                GroupBox {
                    ZStack(alignment: .topLeading) {
                        tabContent(tab: .general) {
                            generalOptions
                        }
                        tabContent(tab: .advanced) {
                            advancedOptions
                        }
                    }
                    .padding(12)
                }
            }

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

    /// `content`, laid out whether or not `tab` is selected, but only shown
    /// and usable when it is.
    private func tabContent(
        tab: Tab,
        @ViewBuilder content: () -> some View,
    ) -> some View {
        let isSelected = self.tab == tab
        return content()
            .opacity(isSelected ? 1 : 0)
            .disabled(!isSelected)
            .accessibilityHidden(!isSelected)
    }

    /// A row of options: `title`, trailing-aligned in a column of fixed
    /// width, so both tabs' rows line up, then `content`. They're aligned by
    /// `alignment`: their first lines of text, unless `content` has none.
    private func optionRow(
        title: String,
        alignment: VerticalAlignment = .firstTextBaseline,
        @ViewBuilder content: () -> some View,
    ) -> some View {
        GridRow(alignment: alignment) {
            Text(title)
                .frame(width: Self.labelWidth, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - General options

    private var generalOptions: some View {
        Grid(alignment: .leading, verticalSpacing: 12) {
            optionRow(title: "Git access:") {
                gitAccessField
            }
            optionRow(title: "Environment file:") {
                envFileField
            }
            optionRow(title: "Extra skills:", alignment: .top) {
                skillsField
            }
            optionRow(title: "Permission mode:") {
                permissionModeField
            }
        }
    }

    private var gitAccessField: some View {
        HStack {
            Picker("Git access", selection: $options.gitAccessMode) {
                Text("Read-only").tag(GitAccessMode.read)
                Text("Read-write").tag(GitAccessMode.write)
            }
            .labelsHidden()
            .fixedSize()
            switch options.gitAccessMode {
            case .read:
                EmptyView()
            case .write:
                // Tighter than a `Label`'s spacing between icon and text.
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Claude can commit and rewrite history.")
                }
                .foregroundStyle(.orange)
            }
        }
    }

    private var envFileField: some View {
        HStack {
            Button("Choose…") {
                Task {
                    if let envFile = await chooseEnvFile() {
                        options.envFile = envFile
                    }
                }
            }
            if let envFile = options.envFile {
                Text(displayPath(path: envFile))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    options.envFile = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Don't use an environment file")
            } else {
                Text("None")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A list of the host's skills and the extra skills, showing a fixed
    /// number of rows, with a bar of buttons to add and remove extra skills
    /// beneath it, all in one rounded box.
    private var skillsField: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSkills) {
                ForEach(hostSkills, id: \.self) { skill in
                    Text(displayPath(path: skill))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(
                            "Every session gets the skills in ~/.claude/skills.",
                        )
                        .selectionDisabled()
                }
                ForEach(options.addSkills, id: \.self) { skill in
                    Text(displayPath(path: skill))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .listStyle(.plain)
            .alternatingRowBackgrounds(
                hostSkills.isEmpty && options.addSkills.isEmpty
                    ? .disabled
                    : .enabled,
            )
            .environment(\.defaultMinListRowHeight, Self.skillsRowHeight)
            .frame(
                height: CGFloat(Self.skillsVisibleRows) * Self.skillsRowHeight,
            )
            .overlay {
                if hostSkills.isEmpty, options.addSkills.isEmpty {
                    Text("No Extra Skills")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 0) {
                Button {
                    Task {
                        for skill in await chooseSkills()
                            where !options.addSkills.contains(skill)
                        {
                            options.addSkills.append(skill)
                        }
                    }
                } label: {
                    skillsBarIcon(systemName: "plus")
                }
                .help("Add skills")
                Divider()
                    .frame(height: 12)
                Button {
                    options.addSkills.removeAll { skill in
                        selectedSkills.contains(skill)
                    }
                    selectedSkills = []
                } label: {
                    skillsBarIcon(systemName: "minus")
                }
                .help("Remove the selected skills")
                .disabled(selectedSkills.isEmpty)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.separator)
        }
    }

    /// An icon for a button in the bar beneath the skills, sized so the
    /// whole button is easy to click.
    private func skillsBarIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .frame(width: 24, height: 22)
            .contentShape(Rectangle())
    }

    private var permissionModeField: some View {
        Picker("Permission mode", selection: $options.permissionMode) {
            ForEach(permissionModes, id: \.self) { mode in
                Text(mode).tag(mode)
            }
        }
        .labelsHidden()
        .fixedSize()
    }

    /// The permission modes to offer, including the default from
    /// `settings.json` if Claude Code's list doesn't have it.
    private var permissionModes: [String] {
        if Self.claudePermissionModes.contains(options.permissionMode) {
            Self.claudePermissionModes
        } else {
            Self.claudePermissionModes + [options.permissionMode]
        }
    }

    // MARK: - Advanced options

    private var advancedOptions: some View {
        Grid(alignment: .leading, verticalSpacing: 12) {
            optionRow(title: "Model:") {
                TextField("Model", text: $options.model)
                    .labelsHidden()
                    .frame(width: 200)
            }
            optionRow(title: "CPUs:") {
                HStack(spacing: 4) {
                    TextField(
                        "CPUs",
                        value: $options.cpus,
                        format: .number,
                    )
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 40)
                    Stepper(
                        "CPUs",
                        value: $options.cpus,
                        in: 1...max(
                            ProcessInfo.processInfo.activeProcessorCount,
                            options.cpus,
                        ),
                    )
                    .labelsHidden()
                }
                // Typed values below 1 aren't valid; the stepper keeps to
                // its range, but the text field doesn't.
                .onChange(of: options.cpus) {
                    if options.cpus < 1 {
                        options.cpus = 1
                    }
                }
            }
            optionRow(title: "Memory:") {
                TextField(
                    "Memory",
                    text: $options.memory,
                    prompt: Text("e.g. 8G"),
                )
                .labelsHidden()
                .frame(width: 80)
            }
            optionRow(title: "Use host's Claude configs?") {
                Toggle(
                    "Use host's Claude configs?",
                    isOn: $options.copyHostClaudeConfigs,
                )
                .labelsHidden()
            }
        }
    }

    /// `path`, abbreviated with `~` if it's in the home folder.
    private func displayPath(path: String) -> String {
        NSString(string: path).abbreviatingWithTildeInPath
    }
}
