import AppKit

/// The open panels the app shows, as sheets.
extension NSOpenPanel {
    /// Asks for a file of environment variables on `window`, returning its
    /// path, or nil if the user cancels.
    static func chooseEnvFile(window: NSWindow) async -> String? {
        await choosePaths(
            window: window,
            directories: false,
            message: "Choose a file of KEY=VALUE environment variables.",
        ).first
    }

    /// Asks for skill folders on `window`, returning their paths.
    static func chooseSkills(window: NSWindow) async -> [String] {
        await choosePaths(
            window: window,
            directories: true,
            message: "Choose skill folders to add to the session.",
        )
    }

    /// Asks for the `name` executable on `window`, starting in the folder of
    /// `currentPath`, and returns its path, or nil if the user cancels.
    static func chooseExecutable(
        window: NSWindow,
        name: String,
        currentPath: String,
    ) async -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        // Tools are often in hidden folders, like /usr/local/bin.
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: currentPath)
            .deletingLastPathComponent()
        panel.message = "Choose the \(name) executable."
        let response = await panel.beginSheetModal(for: window)
        switch response {
        case .OK:
            return panel.url?.path
        default:
            return nil
        }
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
}
