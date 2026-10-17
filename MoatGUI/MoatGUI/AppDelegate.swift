import AppKit
import MoatKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let sessionManager: SessionManager
    private let settingsManager: SettingsManager

    private let sessionsModel: SessionsModel

    private var mainWindowController: MainWindowController?

    static func main() {
        let application = NSApplication.shared
        // `NSApplication.delegate` is weak, but `run()` doesn't return until
        // the app quits, so this keeps the delegate alive.
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    override init() {
        let environment = HostEnvironment()

        do {
            self.settingsManager = try SettingsManager.load(environment: environment)
        } catch {
            Logger.error("Couldn't load settings: \(error)")
            let alert = NSAlert(error: error)
            alert.messageText = "Moat couldn't read its settings."
            alert.informativeText = """
            Fix or remove \(environment.settingsFile.path), then reopen \
            Moat.

            \(error)
            """
            alert.runModal()
            exit(1)
        }
        self.sessionManager = SessionManager(
            environment: environment,
            settingsManager: settingsManager,
        )
        self.sessionsModel = SessionsModel(
            settingsManager: settingsManager,
            sessionManager: sessionManager,
        )

        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.mainMenu = makeMainMenu()

        sessionsModel.migratePointers()
        sessionsModel.reloadSessions()
        Task {
            await sessionsModel.updateStatuses()
        }

        let mainWindowController = MainWindowController(model: sessionsModel)
        mainWindowController.showWindow(nil)
        self.mainWindowController = mainWindowController

        NSApplication.shared.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication,
    ) -> Bool {
        true
    }

    func applicationShouldTerminate(
        _ sender: NSApplication,
    ) -> NSApplication.TerminateReply {
        let localRunningSessionNames = sessionsModel.localRunningSessionNames
        if localRunningSessionNames.isEmpty {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Quit \(ProcessInfo.processInfo.processName)?"
        alert.informativeText = """
        \(localRunningSessionNames.count) sessions will be stopped:

        \(localRunningSessionNames.joined(separator: "\n"))
        """
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            break
        default:
            return .terminateCancel
        }

        Task {
            await sessionsModel.stopAll()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// The Moat, Edit, and Window menus.
    private func makeMainMenu() -> NSMenu {
        let appName = ProcessInfo.processInfo.processName

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About \(appName)",
            action: #selector(
                NSApplication.orderFrontStandardAboutPanel(_:)
            ),
            keyEquivalent: "",
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q",
        )

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c",
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v",
        )

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m",
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: "",
        )
        NSApplication.shared.windowsMenu = windowMenu

        let mainMenu = NSMenu()
        for menu in [appMenu, editMenu, windowMenu] {
            let item = mainMenu.addItem(
                withTitle: menu.title,
                action: nil,
                keyEquivalent: "",
            )
            item.submenu = menu
        }
        return mainMenu
    }
}
