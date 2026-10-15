import Foundation
import Testing
@testable import MoatKit

struct SessionOptionsTests {
    let fixture: Fixture

    init() throws {
        fixture = try Fixture()
    }

    func load(_ json: String) throws -> SessionOptions {
        try SessionOptions.load(file: fixture.write(json, path: "settings.json"))
    }

    @Test
    func missingFileIsDefaults() throws {
        let missing = fixture.root.appendingPathComponent("missing.json")
        #expect(try SessionOptions.load(file: missing) == SessionOptions())
    }

    @Test
    func missingKeysAreDefaults() throws {
        let options = try load(#"{"model": "sonnet"}"#)
        var expected = SessionOptions()
        expected.model = "sonnet"
        #expect(options == expected)
    }

    @Test
    func loadsAllKeys() throws {
        let options = try load("""
        {
            "addSkills": ["~/a", "/b"],
            "cpus": 4,
            "envFile": "~/tokens.env",
            "gitAccessMode": "write",
            "memory": "8G",
            "model": "sonnet",
            "noClaudeSettings": true,
            "containerPath": "/opt/bin/container",
            "gitPath": "/opt/bin/git",
            "permissionMode": "plan",
            "someFutureKey": 42
        }
        """)
        #expect(options.addSkills == ["~/a", "/b"])
        #expect(options.cpus == 4)
        #expect(options.envFile == "~/tokens.env")
        #expect(options.gitAccessMode == .write)
        #expect(options.memory == "8G")
        #expect(options.model == "sonnet")
        #expect(options.noClaudeSettings == true)
        #expect(options.containerPath == "/opt/bin/container")
        #expect(options.gitPath == "/opt/bin/git")
        #expect(options.permissionMode == "plan")
    }

    @Test(arguments: [
        "{",
        "[]",
        #"{"model": 3}"#,
        #"{"noClaudeSettings": 1}"#,
        #"{"noClaudeSettings": "yes"}"#,
        #"{"containerPath": 1}"#,
        #"{"gitPath": 1}"#,
        #"{"addSkills": "~/a"}"#,
        #"{"addSkills": ["~/a", 2]}"#,
        #"{"gitAccessMode": "admin"}"#,
        #"{"cpus": "4"}"#,
        #"{"memory": 8}"#,
    ])
    func invalid(json: String) throws {
        let url = fixture.root.appendingPathComponent("settings.json")
        #expect(throws: MoatError.invalidSettingsFile(url.path)) {
            try load(json)
        }
    }
}
