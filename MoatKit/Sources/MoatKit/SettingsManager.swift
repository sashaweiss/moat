import Foundation
import Observation

/// Manages Moat settings.
///
/// Settings are persisted in `~/.moat/settings.json` and read on load.
@MainActor
@Observable
public final class SettingsManager {
    public let environment: HostEnvironment

    /// The default options for new sessions.
    public private(set) var sessionOptions = SessionOptions()

    /// Where moat finds its tools on this Mac.
    public private(set) var hostSettings = HostSettings()

    /// The commands moat runs on this Mac, from `hostSettings`.
    public private(set) var hostCommands: HostCommands

    init(environment: HostEnvironment, hostCommands: HostCommands) {
        self.environment = environment
        self.hostCommands = hostCommands
    }

    /// Create a `SettingsManager` loaded with the contents of `settings.json`.
    public static func load(environment: HostEnvironment) throws -> SettingsManager {
        let settingsManager = SettingsManager(
            environment: environment,
            hostCommands: Container.hostCommands(settings: HostSettings()),
        )
        try settingsManager.load()
        return settingsManager
    }

    /// Reload this `SettingsManager` with the current contents of `settings.json`.
    public func load() throws {
        struct SettingsFile: Decodable {
            // Optional, since synthesized decoding doesn't use defaults.
            var sessionDefaults: SessionOptions?
        }

        let file = environment.settingsFile
        var hostSettings = HostSettings()
        var sessionOptions = SessionOptions()

        if FileManager.default.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            do {
                let decoder = JSONDecoder()
                decoder.allowsJSON5 = true
                hostSettings = try decoder.decode(HostSettings.self, from: data)
                sessionOptions = try decoder
                    .decode(SettingsFile.self, from: data)
                    .sessionDefaults ?? SessionOptions()
            } catch {
                throw MoatError.invalidSettingsFile(
                    file.path,
                    reason: String(describing: error),
                )
            }
        }

        self.hostSettings = hostSettings
        self.sessionOptions = sessionOptions
        hostCommands = Container.hostCommands(settings: hostSettings)
    }
}
