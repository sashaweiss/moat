import AppKit
import MoatKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        let settingsManager = SettingsManager(environment: environment)
        let settings: SessionOptions
        do {
            settings = try settingsManager.loadSettings()
        } catch {
            Logger.error("Couldn't load settings: \(error)")
            settings = SessionOptions()
        }
        sessionsModel = SessionsModel(
            settingsManager: settingsManager,
            sessionManager: SessionManager(
                environment: environment,
                commands: Container.sessionCommands(
                    executable: settings.containerPath,
                ),
            ),
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.mainMenu = makeMainMenu()

        sessionsModel.migratePointers()
        sessionsModel.reloadSessions()

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

    /// Confirms quitting, then stops every running session before quitting.
    func applicationShouldTerminate(
        _ sender: NSApplication,
    ) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = "Quit \(ProcessInfo.processInfo.processName)?"
        let runningSessionNames = sessionsModel.runningSessionNames
        if runningSessionNames.isEmpty {
            alert.informativeText = "No sessions are running."
        } else {
            alert.informativeText = """
                These sessions will be stopped:
                \(runningSessionNames.joined(separator: "\n"))
                """
        }
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

    /// The app, Edit, and Window menus.
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
