import Foundation

/// Manages moat's settings, persisted in `~/.moat/settings.json`.
@MainActor
public final class SettingsManager {
    public let environment: HostEnvironment

    public init(environment: HostEnvironment) {
        self.environment = environment
    }

    /// Loads the user's default session options from
    /// `~/.moat/settings.json`.
    public func loadSettings() throws -> SessionOptions {
        try SessionOptions.load(file: environment.settingsFile)
    }
}
