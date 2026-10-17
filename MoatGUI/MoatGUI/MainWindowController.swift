import AppKit
import MoatKit
import SwiftUI

/// The app's one window: a sidebar of sessions, and the selected session's
/// content.
final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private static let addSessionItem = NSToolbarItem.Identifier("addSession")

    private let model: SessionsModel

    init(model: SessionsModel) {
        self.model = model

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
                .fullSizeContentView,
            ],
            backing: .buffered,
            defer: false,
        )
        window.title = ProcessInfo.processInfo.processName

        super.init(window: window)

        // The sidebar calls back into this controller, so it's made after
        // initialization.
        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(
                rootView: SidebarView(
                    model: model,
                    startSession: { [weak self] workspace in
                        self?.startSession(workspace: workspace)
                    },
                    removeSession: { [weak self] session in
                        self?.removeSession(session: session)
                    },
                ),
            ),
        )
        sidebarItem.minimumThickness = 200

        let contentItem = NSSplitViewItem(
            viewController: SessionContentViewController(model: model),
        )

        let splitViewController = NSSplitViewController()
        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(contentItem)

        // Setting the content view controller resizes the window to fit its
        // view, which starts out tiny; so the window is sized afterward.
        window.contentViewController = splitViewController
        window.setContentSize(NSSize(width: 900, height: 600))
        window.contentMinSize = NSSize(width: 600, height: 400)
        window.center()
        // Restores the window's last size and position, if it has one.
        _ = window.setFrameAutosaveName("Main")

        let toolbar = NSToolbar(identifier: "Main")
        toolbar.delegate = self
        window.toolbar = toolbar
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    // MARK: -

    @objc private func addSession(_ sender: Any?) {
        Task {
            await _addSession()
        }
    }

    /// Asks the user to choose a folder, and starts a session for it.
    private func _addSession() async {
        guard let window else {
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add"
        panel.message = "Choose a folder for Claude to work in."
        let response = await panel.beginSheetModal(for: window)
        switch response {
        case .OK:
            break
        default:
            return
        }
        guard let folder = panel.url else {
            return
        }
        await _startSession(workspace: Workspace(folder: folder))
    }

    // MARK: -

    /// Selects the session for `workspace`, asks for the options to start it
    /// with, and starts it, unless it's already running.
    func startSession(workspace: Workspace) {
        Task {
            await _startSession(workspace: workspace)
        }
    }

    /// Selects the session for `workspace` and runs it if necessary, asking for
    /// session options first.
    private func _startSession(workspace: Workspace) async {
        model.selectedWorkspace = workspace

        switch model.status(workspace: workspace) {
        case nil, .stopped, .missing:
            break
        case .idle, .busy, .runningElsewhere:
            return
        }

        guard let options = await askForOptions(workspace: workspace) else {
            return
        }

        model.start(workspace: workspace, options: options)
    }

    /// Shows a sheet asking for options with which to start a session for `workspace`.
    /// - Returns: the options, or `nil` if cancelled.
    private func askForOptions(workspace: Workspace) async -> SessionOptions? {
        guard let window else {
            return nil
        }

        var options: SessionOptions?
        let sheet = NSWindow()
        sheet.contentViewController = NSHostingController(
            rootView: StartSessionOptionsView(
                name: model.sessionName(workspace: workspace),
                workspace: workspace,
                options: model.defaultOptions,
                hostSkills: model.hostSkills(),
                chooseEnvFile: { [weak sheet] in
                    guard let sheet else {
                        return nil
                    }
                    return await Self.choosePaths(
                        window: sheet,
                        directories: false,
                        message:
                        "Choose a file of KEY=VALUE environment variables.",
                    ).first
                },
                chooseSkills: { [weak sheet] in
                    guard let sheet else {
                        return []
                    }
                    return await Self.choosePaths(
                        window: sheet,
                        directories: true,
                        message: "Choose skill folders to add to the session.",
                    )
                },
                finish: { [weak window, weak sheet] chosenOptions in
                    options = chosenOptions
                    if let window, let sheet {
                        window.endSheet(sheet)
                    }
                },
            ),
        )

        _ = await window.beginSheet(sheet)
        return options
    }

    /// Shows an open panel as a sheet on `window`, asking for files, or for
    /// folders (several at once) if `directories` is true, and returns their
    /// paths, or none if the user cancels.
    private static func choosePaths(
        window: NSWindow,
        directories: Bool,
        message: String,
    ) async -> [String] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = directories
        panel.message = message
        let response = await panel.beginSheetModal(for: window)
        switch response {
        case .OK:
            return panel.urls.map(\.path)
        default:
            return []
        }
    }

    // MARK: -

    /// Asks the user to confirm removing `session`, and removes it.
    func removeSession(session: SessionMetadata) {
        Task {
            await _removeSession(session: session)
        }
    }

    private func _removeSession(session: SessionMetadata) async {
        guard let window else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "Remove session \"\(session.name)\"?"
        alert.informativeText = """
            This permanently deletes Claude history and settings for \
            "\(session.workspace.path)".
            """
        alert.addButton(withTitle: "Remove").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        let response = await alert.beginSheetModal(for: window)
        switch response {
        case .alertFirstButtonReturn:
            model.remove(session: session)
        default:
            break
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(
        _ toolbar: NSToolbar,
    ) -> [NSToolbarItem.Identifier] {
        // Items before the separator sit above the sidebar; the flexible space
        // pushes the add button against the sidebar's right edge.
        [.flexibleSpace, Self.addSessionItem, .sidebarTrackingSeparator]
    }

    func toolbarAllowedItemIdentifiers(
        _ toolbar: NSToolbar,
    ) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool,
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.addSessionItem else {
            return nil
        }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.toolTip = "Add a session for a folder"
        item.image = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: "Add Session",
        )
        item.target = self
        item.action = #selector(addSession(_:))
        return item
    }
}
