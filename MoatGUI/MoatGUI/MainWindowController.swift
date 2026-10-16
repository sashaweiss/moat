import AppKit
import SwiftUI

/// The app's one window: a sidebar of sessions, and the selected session's
/// content.
final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private static let addSessionItem = NSToolbarItem.Identifier("addSession")

    private let model: SessionsModel

    init(model: SessionsModel) {
        self.model = model

        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(
                rootView: SidebarView(model: model),
            ),
        )
        sidebarItem.minimumThickness = 200

        let contentItem = NSSplitViewItem(
            viewController: SessionContentViewController(model: model),
        )

        let splitViewController = NSSplitViewController()
        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(contentItem)

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
        // Setting the content view controller resizes the window to fit its
        // view, which starts out tiny; so the window is sized afterward.
        window.contentViewController = splitViewController
        window.setContentSize(NSSize(width: 900, height: 600))
        window.contentMinSize = NSSize(width: 600, height: 400)
        window.center()
        // Restores the window's last size and position, if it has one.
        _ = window.setFrameAutosaveName("Main")

        super.init(window: window)

        let toolbar = NSToolbar(identifier: "Main")
        toolbar.delegate = self
        window.toolbar = toolbar
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    /// Asks for a folder, and adds a session for it.
    @objc private func addSession(_ sender: Any?) {
        guard let window else {
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Add"
        panel.message = "Choose a folder for Claude to work in."
        panel.beginSheetModal(for: window) { [model] response in
            guard response == .OK, let folder = panel.url else {
                return
            }
            model.add(folder: folder)
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
