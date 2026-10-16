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
        #expect(throws: MoatError.invalidSettingsFile(url.path)) {
            try SettingsManager.load(environment: fixture.environment)
        }
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
            settingsManager.hostSettings.containerPath == "/opt/bin/container"
        )
        #expect(
            settingsManager.hostCommands.checkSystem
                == ["/opt/bin/container", "system", "status"]
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
        #expect(throws: MoatError.invalidSettingsFile(url.path)) {
            try settingsManager.load()
        }
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
        #expect(throws: MoatError.invalidSettingsFile(url.path)) {
            try settingsManager.load()
        }
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
}
