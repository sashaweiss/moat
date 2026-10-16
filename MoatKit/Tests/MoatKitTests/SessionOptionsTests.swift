import Foundation
import Testing
@testable import MoatKit

struct SessionOptionsTests {
    func decode(_ json: String) throws -> SessionOptions {
        try JSONDecoder().decode(SessionOptions.self, from: Data(json.utf8))
    }

    @Test
    func missingKeysAreDefaults() throws {
        let options = try decode(#"{"model": "sonnet"}"#)
        var expected = SessionOptions()
        expected.model = "sonnet"
        #expect(options == expected)
    }

    @Test
    func decodesAllKeys() throws {
        let options = try decode("""
        {
            "addSkills": ["~/a", "/b"],
            "cpus": 4,
            "envFile": "~/tokens.env",
            "gitAccessMode": "write",
            "memory": "8G",
            "model": "sonnet",
            "noClaudeSettings": true,
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
        #expect(options.permissionMode == "plan")
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
        #"{"cpus": "4"}"#,
        #"{"memory": 8}"#,
    ])
    func invalid(json: String) throws {
        #expect(throws: DecodingError.self) {
            try decode(json)
        }
    }
}
