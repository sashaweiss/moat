import AppKit
import MoatKit
import SwiftUI

/// A pane of the Settings window.
enum SettingsPane: CaseIterable {
    case sessionDefaults
    case toolLocations

    var title: String {
        switch self {
        case .sessionDefaults: "Session Defaults"
        case .toolLocations: "Tool Locations"
        }
    }

    var systemImage: String {
        switch self {
        case .sessionDefaults: "slider.horizontal.3"
        case .toolLocations: "wrench.and.screwdriver"
        }
    }
}

// MARK: -

/// The Settings window: a tab for each pane, which edits `settings.json`.
final class SettingsWindowController: NSWindowController {
    private let settingsManager: SettingsManager
    private let sessionsModel: SessionsModel

    /// Each pane's controller, whose view is remade on each `show()`.
    private var paneControllers: [SettingsPane: NSHostingController<AnyView>] = [:]

    init(settingsManager: SettingsManager, sessionsModel: SessionsModel) {
        self.settingsManager = settingsManager
        self.sessionsModel = sessionsModel

        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false,
        )
        window.toolbarStyle = .preference
        // This controller keeps the window to show again after it's closed.
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let tabViewController = NSTabViewController()
        tabViewController.tabStyle = .toolbar
        for pane in SettingsPane.allCases {
            // Each pane sizes the window to fit it while it's selected.
            let controller = NSHostingController(rootView: AnyView(EmptyView()))
            controller.sizingOptions = .preferredContentSize
            paneControllers[pane] = controller

            let item = NSTabViewItem(viewController: controller)
            item.label = pane.title
            item.image = NSImage(
                systemSymbolName: pane.systemImage,
                accessibilityDescription: pane.title,
            )
            tabViewController.addTabViewItem(item)
        }
        window.contentViewController = tabViewController

        window.center()
        // Restores the window's last position, if it has one.
        _ = window.setFrameAutosaveName("Settings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    /// Shows the window. If it isn't already showing, first rereads
    /// `settings.json` (in case it's been edited by hand) and remakes the
    /// panes, so they show the current settings and images. If the file
    /// can't be read, says so, and shows the settings from before.
    func show() async {
        guard let window else {
            return
        }
        if window.isVisible {
            showWindow(nil)
            return
        }

        var loadError: (any Error)?
        do {
            try settingsManager.load()
        } catch {
            Logger.error("Couldn't reload settings: \(error)")
            loadError = error
        }
        let images = await sessionsModel.moatImages()
        for (pane, controller) in paneControllers {
            controller.rootView = AnyView(
                // Unique ID so the view is never reused.
                paneView(pane: pane, images: images)
                    .id(UUID()),
            )
        }
        showWindow(nil)
        if let loadError {
            presentAlert(
                message: "Moat couldn't read its settings.",
                error: loadError,
            )
        }
    }

    private func paneView(
        pane: SettingsPane,
        images: [String],
    ) -> AnyView {
        switch pane {
        case .sessionDefaults:
            AnyView(SessionDefaultsView(
                options: settingsManager.sessionOptions,
                hostSkills: sessionsModel.hostSkills(),
                images: images,
                chooseEnvFile: { [weak self] in
                    guard let window = self?.window else {
                        return nil
                    }
                    return await NSOpenPanel.chooseEnvFile(window: window)
                },
                chooseSkills: { [weak self] in
                    guard let window = self?.window else {
                        return []
                    }
                    return await NSOpenPanel.chooseSkills(window: window)
                },
                save: { [weak self] options in
                    self?.save(sessionOptions: options)
                },
            ))
        case .toolLocations:
            AnyView(ToolLocationsView(
                hostSettings: settingsManager.hostSettings,
                chooseExecutable: { [weak self] name, currentPath in
                    guard let window = self?.window else {
                        return nil
                    }
                    return await NSOpenPanel.chooseExecutable(
                        window: window,
                        name: name,
                        currentPath: currentPath,
                    )
                },
                save: { [weak self] hostSettings in
                    self?.save(hostSettings: hostSettings)
                },
            ))
        }
    }

    // MARK: -

    private func save(sessionOptions: SessionOptions) {
        do {
            try settingsManager.save(sessionOptions: sessionOptions)
        } catch {
            Logger.error("Couldn't save session defaults: \(error)")
            presentAlert(
                message: "Moat couldn't save its settings.",
                error: error,
            )
        }
    }

    private func save(hostSettings: HostSettings) {
        do {
            try settingsManager.save(hostSettings: hostSettings)
        } catch {
            Logger.error("Couldn't save tool locations: \(error)")
            presentAlert(
                message: "Moat couldn't save its settings.",
                error: error,
            )
        }
    }

    /// Shows an alert about `error` as a sheet, unless one is already
    /// showing (e.g., since saving failed on an earlier keystroke).
    private func presentAlert(message: String, error: any Error) {
        guard let window, window.attachedSheet == nil else {
            return
        }
        let alert = NSAlert(error: error)
        alert.messageText = message
        alert.informativeText = String(describing: error)
        alert.beginSheetModal(for: window, completionHandler: nil)
    }
}
