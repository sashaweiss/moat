import Foundation
import Testing
@testable import MoatKit

@MainActor
struct SettingsManagerTests {
    let fixture: Fixture
    let settingsManager: SettingsManager

    init() throws {
        fixture = try Fixture()
        settingsManager = try SettingsManager.load(environment: fixture.environment)
    }

    @Test
    func withoutFileUsesDefaults() {
        #expect(settingsManager.sessionOptions == SessionOptions())
        #expect(settingsManager.hostSettings == HostSettings())
    }

    @Test
    func initFailsOnInvalidSettingsFile() throws {
        let url = try fixture.write(
            #"{"gitPath": 1}"#,
            path: ".moat/settings.json",
            base: fixture.home,
        )
        let error = #expect(throws: MoatError.self) {
            try SettingsManager.load(environment: fixture.environment)
        }
        #expect(invalidSettingsFilePath(error) == url.path)
    }

    @Test
    func loadReadsSettingsFile() throws {
        try fixture.write(
            """
            {
                "containerPath": "/opt/bin/container",
                "gitPath": "/opt/bin/git",
                "sessionDefaults": {
                    "model": "sonnet"
                }
            }
            """,
            path: ".moat/settings.json",
            base: fixture.home,
        )
        try settingsManager.load()
        #expect(settingsManager.sessionOptions.model == "sonnet")
        #expect(
            settingsManager.hostSettings.containerPath == "/opt/bin/container",
        )
        #expect(
            settingsManager.hostCommands.checkSystem
                == ["/opt/bin/container", "system", "status"],
        )
        #expect(settingsManager.hostCommands.gitPath == "/opt/bin/git")
    }

    @Test
    func failedLoadKeepsCurrentSettings() throws {
        let url = try fixture.write(
            #"{"sessionDefaults": {"model": "sonnet"}}"#,
            path: ".moat/settings.json",
            base: fixture.home,
        )
        try settingsManager.load()
        try fixture.write(
            #"{"gitPath": 1}"#,
            path: ".moat/settings.json",
            base: fixture.home,
        )
        let error = #expect(throws: MoatError.self) {
            try settingsManager.load()
        }
        #expect(invalidSettingsFilePath(error) == url.path)
        #expect(settingsManager.sessionOptions.model == "sonnet")
        #expect(settingsManager.hostSettings == HostSettings())
    }

    @Test(arguments: [
        "{",
        #"{"gitPath": 1}"#,
        #"{"sessionDefaults": {"model": 3}}"#,
        #"{"sessionDefaults": "opus"}"#,
    ])
    func invalidSettingsFile(json: String) throws {
        let url = try fixture.write(
            json,
            path: ".moat/settings.json",
            base: fixture.home,
        )
        let error = #expect(throws: MoatError.self) {
            try settingsManager.load()
        }
        #expect(invalidSettingsFilePath(error) == url.path)
    }

    @Test
    func sessionOptionsAreOnlyReadFromSessionDefaults() throws {
        try fixture.write(
            #"{"model": "sonnet"}"#,
            path: ".moat/settings.json",
            base: fixture.home,
        )
        try settingsManager.load()
        #expect(settingsManager.sessionOptions == SessionOptions())
    }

    @Test
    func settingsFileMayBeJSON5() throws {
        try fixture.write(
            """
            {
                // Comments, unquoted keys, and trailing commas are fine.
                gitPath: "/opt/bin/git",
                sessionDefaults: {
                    model: "sonnet",
                },
            }
            """,
            path: ".moat/settings.json",
            base: fixture.home,
        )
        try settingsManager.load()
        #expect(settingsManager.hostSettings.gitPath == "/opt/bin/git")
        #expect(settingsManager.sessionOptions.model == "sonnet")
    }

    @Test
    func saveWritesSettingsThatLoad() throws {
        var sessionOptions = SessionOptions()
        sessionOptions.model = "sonnet"
        sessionOptions.envFile = "/tokens.env"
        var hostSettings = HostSettings()
        hostSettings.containerPath = "/opt/bin/container"
        try settingsManager.save(sessionOptions: sessionOptions)
        try settingsManager.save(hostSettings: hostSettings)
        #expect(settingsManager.sessionOptions == sessionOptions)
        #expect(settingsManager.hostSettings == hostSettings)
        #expect(
            settingsManager.hostCommands.checkSystem
                == ["/opt/bin/container", "system", "status"],
        )

        let reloaded = try SettingsManager.load(
            environment: fixture.environment,
        )
        #expect(reloaded.sessionOptions == sessionOptions)
        #expect(reloaded.hostSettings == hostSettings)
    }

    @Test
    func saveKeepsTheOtherSettings() throws {
        try fixture.write(
            """
            {
                gitPath: "/opt/bin/git",
                sessionDefaults: {model: "sonnet"},
            }
            """,
            path: ".moat/settings.json",
            base: fixture.home,
        )
        try settingsManager.load()

        var sessionOptions = settingsManager.sessionOptions
        sessionOptions.cpus = 4
        try settingsManager.save(sessionOptions: sessionOptions)
        var hostSettings = settingsManager.hostSettings
        hostSettings.containerPath = "/opt/bin/container"
        try settingsManager.save(hostSettings: hostSettings)

        try settingsManager.load()
        #expect(settingsManager.hostSettings.gitPath == "/opt/bin/git")
        #expect(
            settingsManager.hostSettings.containerPath == "/opt/bin/container",
        )
        #expect(settingsManager.sessionOptions.model == "sonnet")
        #expect(settingsManager.sessionOptions.cpus == 4)
    }

    @Test
    func saveWritesThroughSymlink() throws {
        let target = try fixture.write(
            #"{"gitPath": "/opt/bin/git"}"#,
            path: "dotfiles/moat-settings.json",
            base: fixture.home,
        )
        let link = fixture.environment.settingsFile
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: target,
        )
        try settingsManager.load()

        var sessionOptions = settingsManager.sessionOptions
        sessionOptions.model = "sonnet"
        try settingsManager.save(sessionOptions: sessionOptions)

        #expect(
            try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
                == target.path,
        )
        let reloaded = try SettingsManager.load(
            environment: fixture.environment,
        )
        #expect(reloaded.hostSettings.gitPath == "/opt/bin/git")
        #expect(reloaded.sessionOptions.model == "sonnet")
    }
}
