import AppKit
import SwiftUI

/// The app's one window: a sidebar of sessions, and the selected session's
/// content.
final class MainWindowController: NSWindowController {
    init(model: SessionsModel) {
        let sidebarItem = NSSplitViewItem(
            sidebarWithViewController: NSHostingController(
                rootView: SidebarView(model: model),
            ),
        )
        sidebarItem.minimumThickness = 200

        // Empty for now; this will show the selected session.
        let contentViewController = NSViewController()
        contentViewController.view = NSView()
        let contentItem = NSSplitViewItem(viewController: contentViewController)

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }
}
