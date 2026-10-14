import Foundation
import Testing
@testable import MoatKit

struct MoatSettingsTests {
    let fixture: Fixture

    init() throws {
        fixture = try Fixture()
    }

    func load(_ json: String) throws -> MoatSettings {
        try MoatSettings.load(file: fixture.write(json, path: "settings.json"))
    }

    @Test
    func missingFileIsEmpty() throws {
        let missing = fixture.root.appendingPathComponent("missing.json")
        let settings = try MoatSettings.load(file: missing)
        #expect(settings == MoatSettings())
    }

    @Test
    func loadsAllKeys() throws {
        let settings = try load("""
        {
            "addSkills": ["~/a", "/b"],
            "envFile": "~/tokens.env",
            "gitAccessMode": "write",
            "model": "sonnet",
            "noClaudeSettings": true,
            "permissionMode": "plan",
            "someFutureKey": 42
        }
        """)
        #expect(settings.addSkills == ["~/a", "/b"])
        #expect(settings.envFile == "~/tokens.env")
        #expect(settings.gitAccessMode == .write)
        #expect(settings.model == "sonnet")
        #expect(settings.noClaudeSettings == true)
        #expect(settings.permissionMode == "plan")
    }

    @Test(arguments: [
        "{",
        "[]",
        #"{"model": 3}"#,
        #"{"noClaudeSettings": 1}"#,
        #"{"noClaudeSettings": "yes"}"#,
        #"{"addSkills": "~/a"}"#,
        #"{"addSkills": ["~/a", 2]}"#,
        #"{"gitAccessMode": "admin"}"#,
    ])
    func invalid(json: String) throws {
        let url = fixture.root.appendingPathComponent("settings.json")
        #expect(throws: MoatError.invalidSettingsFile(url.path)) {
            try load(json)
        }
    }

    @Test
    func applyOverridesDefaults() {
        var settings = MoatSettings()
        settings.addSkills = ["~/settings-skill"]
        settings.model = "sonnet"
        settings.noClaudeSettings = true

        var options = SessionOptions(workspace: "/w")
        options.additionalSkills = ["~/cli-skill"]
        settings.apply(options: &options)

        #expect(options.additionalSkills == ["~/cli-skill", "~/settings-skill"])
        #expect(options.model == "sonnet")
        #expect(options.permissionMode == "auto")
        #expect(options.gitAccessMode == .read)
        #expect(options.seedsClaudeSettings == false)
    }

    @Test
    func applyEmptySettingsChangesNothing() {
        var options = SessionOptions(workspace: "/w")
        MoatSettings().apply(options: &options)
        #expect(options == SessionOptions(workspace: "/w"))
    }
}
