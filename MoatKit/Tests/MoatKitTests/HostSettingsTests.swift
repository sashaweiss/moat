import Foundation
import Testing
@testable import MoatKit

struct HostSettingsTests {
    func decode(_ json: String) throws -> HostSettings {
        try JSONDecoder().decode(HostSettings.self, from: Data(json.utf8))
    }

    @Test
    func decodesAllKeys() throws {
        let settings = try decode("""
        {
            "containerPath": "/opt/bin/container",
            "gitPath": "/opt/bin/git",
            "model": "sonnet"
        }
        """)
        #expect(settings.containerPath == "/opt/bin/container")
        #expect(settings.gitPath == "/opt/bin/git")
    }

    @Test
    func missingKeysAreDefaults() throws {
        let settings = try decode(#"{"gitPath": "/opt/bin/git"}"#)
        var expected = HostSettings()
        expected.gitPath = "/opt/bin/git"
        #expect(settings == expected)
    }

    @Test(arguments: [
        "{",
        #"{"containerPath": 1}"#,
        #"{"gitPath": 1}"#,
    ])
    func invalid(json: String) throws {
        #expect(throws: DecodingError.self) {
            try decode(json)
        }
    }
}
