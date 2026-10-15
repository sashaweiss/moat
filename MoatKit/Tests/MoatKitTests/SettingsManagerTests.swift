import Foundation
import Testing
@testable import MoatKit

@MainActor
struct SettingsManagerTests {
    let fixture: Fixture
    let settingsManager: SettingsManager

    init() throws {
        fixture = try Fixture()
        settingsManager = SettingsManager(environment: fixture.environment)
    }

    @Test
    func loadSettingsWithoutFileIsDefaults() throws {
        #expect(try settingsManager.loadSettings() == SessionOptions())
    }

    @Test
    func loadSettingsReadsSettingsFile() throws {
        try fixture.write(
            #"{"model": "sonnet"}"#,
            path: ".moat/settings.json",
            base: fixture.home,
        )
        #expect(try settingsManager.loadSettings().model == "sonnet")
    }
}
