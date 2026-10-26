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
        let file = environment.settingsFile
        var settings = SettingsFile()

        if FileManager.default.fileExists(atPath: file.path) {
            let data = try Data(contentsOf: file)
            do {
                let decoder = JSONDecoder()
                decoder.allowsJSON5 = true
                settings = try decoder.decode(SettingsFile.self, from: data)
            } catch {
                throw MoatError.invalidSettingsFile(
                    file.path,
                    reason: String(describing: error),
                )
            }
        }

        hostSettings = settings.hostSettings
        sessionOptions = settings.sessionDefaults
        hostCommands = Container.hostCommands(settings: hostSettings)
    }

    /// Saves `sessionOptions` as the `sessionDefaults` in `settings.json`,
    /// with the current `hostSettings`, and uses them.
    public func save(sessionOptions: SessionOptions) throws {
        try write(settings: SettingsFile(
            hostSettings: hostSettings,
            sessionDefaults: sessionOptions,
        ))
        self.sessionOptions = sessionOptions
    }

    /// Saves `hostSettings` in `settings.json`, with the current
    /// `sessionOptions`, and uses them.
    public func save(hostSettings: HostSettings) throws {
        try write(settings: SettingsFile(
            hostSettings: hostSettings,
            sessionDefaults: sessionOptions,
        ))
        self.hostSettings = hostSettings
        hostCommands = Container.hostCommands(settings: hostSettings)
    }

    /// Replaces `settings.json` with `settings`. Follows symlinks.
    private func write(settings: SettingsFile) throws {
        try FileManager.default.createDirectory(
            at: environment.moatDirectory,
            withIntermediateDirectories: true,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        let file = Filesystem.resolveSymlinks(environment.settingsFile)
        try encoder.encode(settings).write(to: file, options: .atomic)
    }
}

// MARK: -

/// The contents of `settings.json`: `HostSettings` at the top level, and
/// `SessionOptions` as the `sessionDefaults`.
private struct SettingsFile: Codable {
    private enum CodingKeys: String, CodingKey {
        case sessionDefaults
    }

    var hostSettings = HostSettings()
    var sessionDefaults = SessionOptions()

    init() {}

    init(hostSettings: HostSettings, sessionDefaults: SessionOptions) {
        self.hostSettings = hostSettings
        self.sessionDefaults = sessionDefaults
    }

    init(from decoder: any Decoder) throws {
        hostSettings = try HostSettings(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionDefaults = try container
            .decodeIfPresent(SessionOptions.self, forKey: .sessionDefaults)
            ?? sessionDefaults
    }

    func encode(to encoder: any Encoder) throws {
        try hostSettings.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionDefaults, forKey: .sessionDefaults)
    }
}
