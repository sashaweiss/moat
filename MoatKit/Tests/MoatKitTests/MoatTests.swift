import Foundation
import Testing
@testable import MoatKit

struct MoatTests {
    let fixture: Fixture

    init() throws {
        fixture = try Fixture()
    }

    var sessions: URL {
        fixture.home.appendingPathComponent(".moat/sessions")
    }

    var hash: String {
        Moat.hash(workspace: fixture.workspace)
    }

    var claudeSettingsFile: URL {
        sessions.appendingPathComponent("\(hash)/settings.json")
    }

    func prepare(
        _ configure: (inout SessionOptions) -> Void = { _ in },
    ) async throws -> VMLaunchSpec {
        var options = fixture.options
        configure(&options)
        return try await fixture.moat().prepare(options)
    }

    /// The (name, source path) of each skill mounted by `spec`.
    func skills(spec: VMLaunchSpec) -> [(String, String)] {
        spec.mounts
            .filter { $0.destination.hasPrefix("/home/robot/.claude/skills/") }
            .map { (URL(fileURLWithPath: $0.destination).lastPathComponent, $0.source.path) }
    }

    @Test
    func defaults() async throws {
        let spec = try await prepare()
        #expect(spec.envFile == nil)
        #expect(skills(spec: spec).isEmpty)
        #expect(spec.command == ["claude", "--permission-mode", "auto", "--model", "opus"])
    }

    @Test
    func resolvesWorkspaceSymlink() async throws {
        let link = fixture.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.workspace)
        let spec = try await prepare { $0.workspace = link.path }
        #expect(spec.workingDirectory == fixture.workspace.path)
    }

    @Test
    func workspaceMustBeADirectory() async throws {
        let file = try fixture.write("", path: "file")
        await #expect(throws: MoatError.notADirectory(file.path)) {
            try await prepare { $0.workspace = file.path }
        }
        await #expect(throws: MoatError.notADirectory("/nonexistent")) {
            try await prepare { $0.workspace = "/nonexistent" }
        }
    }

    @Test
    func invalidOptionsDoNotWriteState() async throws {
        await #expect(throws: MoatError.self) {
            try await prepare { $0.workspace = "/nonexistent" }
        }
        let moat = fixture.home.appendingPathComponent(".moat")
        #expect(!FileManager.default.fileExists(atPath: moat.path))
    }

    @Test
    func envFile() async throws {
        let envFile = try fixture.write("A=1", path: "tokens.env")
        let spec = try await prepare { $0.envFile = envFile.path }
        #expect(spec.envFile?.path == envFile.path)
    }

    @Test
    func envFileMustBeAFile() async throws {
        let missing = fixture.root.appendingPathComponent("missing.env").path
        await #expect(throws: MoatError.notAFile(missing)) {
            try await prepare { $0.envFile = missing }
        }
        await #expect(throws: MoatError.notAFile(fixture.workspace.path)) {
            try await prepare { $0.envFile = fixture.workspace.path }
        }
    }

    @Test
    func hostSkillsAreFiltered() async throws {
        let hostSkills = try fixture.makeDirectory(".claude/skills", base: fixture.home)
        try fixture.makeDirectory("zeta", base: hostSkills)
        try fixture.makeDirectory("alpha", base: hostSkills)
        try fixture.makeDirectory(".hidden", base: hostSkills)
        try fixture.write("", path: "not-a-skill.md", base: hostSkills)
        let linkedSkill = try fixture.makeDirectory("elsewhere/linked")
        try FileManager.default.createSymbolicLink(
            at: hostSkills.appendingPathComponent("linked"),
            withDestinationURL: linkedSkill,
        )

        let skills = Dictionary(uniqueKeysWithValues: skills(spec: try await prepare()))
        #expect(skills.keys.sorted() == ["alpha", "linked", "zeta"])
        #expect(skills["linked"] == linkedSkill.path)
    }

    @Test
    func additionalSkills() async throws {
        try fixture.makeDirectory(".claude/skills/host", base: fixture.home)
        let extra = try fixture.makeDirectory("extra")
        let skills = skills(spec: try await prepare { $0.additionalSkills = [extra.path] })
        #expect(skills.map(\.0) == ["host", "extra"])
        #expect(skills[1].1 == extra.path)
    }

    @Test
    func additionalSkillMustBeADirectory() async throws {
        let missing = fixture.root.appendingPathComponent("missing").path
        await #expect(throws: MoatError.notADirectory(missing)) {
            try await prepare { $0.additionalSkills = [missing] }
        }
    }

    @Test
    func duplicateSkill() async throws {
        try fixture.makeDirectory(".claude/skills/dupe", base: fixture.home)
        let other = try fixture.makeDirectory("other/dupe")
        await #expect(throws: MoatError.duplicateSkill("dupe")) {
            try await prepare { $0.additionalSkills = [other.path] }
        }
    }

    @Test
    func spec() async throws {
        let spec = try await prepare {
            $0.permissionMode = "plan"
            $0.model = "sonnet"
            $0.claudeArguments = ["--resume", "-c"]
        }
        #expect(spec.name == "moat.workspace")
        #expect(spec.image == "moat:latest")
        #expect(spec.cpus == 2)
        #expect(spec.memory == "4G")
        #expect(spec.user == "robot")
        #expect(spec.workingDirectory == fixture.workspace.path)
        #expect(spec.envFile == nil)
        #expect(spec.command == [
            "claude",
            "--permission-mode",
            "plan",
            "--model",
            "sonnet",
            "--resume",
            "-c",
        ])
    }

    @Test
    func mounts() async throws {
        try fixture.makeDirectory(".claude/skills/skill", base: fixture.home)
        let spec = try await prepare()
        let state = sessions.appendingPathComponent(hash)
        let moat = fixture.home.appendingPathComponent(".moat")
        let skill = fixture.home.appendingPathComponent(".claude/skills/skill")
        #expect(spec.mounts.map(\.source.path) == [
            state.path,
            moat.appendingPathComponent("credentials.json").path,
            sessions.appendingPathComponent("\(hash).claude.json").path,
            sessions.appendingPathComponent("\(hash).CLAUDE.md").path,
            skill.path,
            fixture.workspace.path,
        ])
        #expect(spec.mounts.map(\.destination) == [
            "/home/robot/.claude",
            "/home/robot/.claude/.credentials.json",
            "/home/robot/.claude.json",
            "/home/robot/.claude/CLAUDE.md",
            "/home/robot/.claude/skills/skill",
            fixture.workspace.path,
        ])
        #expect(spec.mounts.map(\.access) == [
            .readWrite,
            .readWrite,
            .readWrite,
            .readOnly,
            .readOnly,
            .readWrite,
        ])
    }

    @Test
    func writesState() async throws {
        _ = try await prepare()
        let fileManager = FileManager.default
        let credentials = fixture.home.appendingPathComponent(".moat/credentials.json")
        #expect(fileManager.fileExists(atPath: credentials.path))
        #expect(Filesystem.isDirectory(sessions.appendingPathComponent(hash)))
        let pointer = sessions.appendingPathComponent("\(hash).pointer")
        #expect(try fixture.read(pointer) == fixture.workspace.path)

        let claudeJSONFile = sessions.appendingPathComponent("\(hash).claude.json")
        let claudeJSON = try fixture.readJSON(claudeJSONFile)
        #expect(claudeJSON["hasCompletedOnboarding"] as? Bool == true)
        #expect(claudeJSON["hasSeenAutoModeEntryWarning"] as? Bool == true)
        let projects = claudeJSON["projects"] as? NSDictionary
        let project = projects?[fixture.workspace.path] as? NSDictionary
        #expect(project?["hasTrustDialogAccepted"] as? Bool == true)
    }

    @Test
    func preservesExistingState() async throws {
        let credentials = try fixture.write(
            "secret",
            path: ".moat/credentials.json",
            base: fixture.home,
        )
        let claudeJSON = try fixture.write("{}", path: "\(hash).claude.json", base: sessions)
        let settings = try fixture.write("{}", path: "\(hash)/settings.json", base: sessions)
        _ = try await prepare()
        #expect(try fixture.read(credentials) == "secret")
        #expect(try fixture.read(claudeJSON) == "{}")
        #expect(try fixture.read(settings) == "{}")
    }

    @Test
    func seedsClaudeSettingsFromHost() async throws {
        try fixture.write(
            #"{"theme": "dark", "nested": {"a": [1, true]}}"#,
            path: ".claude/settings.json",
            base: fixture.home,
        )
        _ = try await prepare()
        let settings = try fixture.readJSON(claudeSettingsFile)
        #expect(settings["theme"] as? String == "dark")
        #expect(settings["autoMemoryDirectory"] as? String == "~/.claude/memory")
        #expect((settings["nested"] as? NSDictionary)?["a"] as? NSArray == [1, true])
    }

    @Test
    func doesNotSeedClaudeSettingsWhenDisabled() async throws {
        try fixture.write(#"{"theme": "dark"}"#, path: ".claude/settings.json", base: fixture.home)
        _ = try await prepare { $0.seedsClaudeSettings = false }
        let settings = try fixture.readJSON(claudeSettingsFile)
        #expect(settings == ["autoMemoryDirectory": "~/.claude/memory"])
    }

    @Test
    func invalidHostClaudeSettings() async throws {
        let url = try fixture.write("[]", path: ".claude/settings.json", base: fixture.home)
        await #expect(throws: MoatError.invalidSettingsFile(url.path)) {
            try await prepare()
        }
        try fixture.write("{", path: ".claude/settings.json", base: fixture.home)
        await #expect(throws: MoatError.invalidSettingsFile(url.path)) {
            try await prepare()
        }
    }

    @Test
    func claudeMD() async throws {
        let prologue = claudePrologue
        #expect(prologue.hasPrefix("# Prologue"))
        let claudeMD = sessions.appendingPathComponent("\(hash).CLAUDE.md")

        _ = try await prepare()
        #expect(try fixture.read(claudeMD) == prologue)

        // Rewritten every time, to pick up changes to the host's CLAUDE.md.
        try fixture.write("host instructions", path: ".claude/CLAUDE.md", base: fixture.home)
        _ = try await prepare()
        #expect(try fixture.read(claudeMD) == prologue + "\n\nhost instructions")
    }

    @Test
    func gitMountsAreReadOnlyByDefault() async throws {
        try await fixture.git("init", "-q", ".", directory: fixture.workspace)
        let nested = try fixture.makeDirectory("nested", base: fixture.workspace)
        try await fixture.git("init", "-q", ".", directory: nested)

        let spec = try await prepare()
        let gitMounts = spec.mounts.suffix(2)
        #expect(gitMounts.map(\.source.path) == [
            fixture.workspace.appendingPathComponent(".git").path,
            nested.appendingPathComponent(".git").path,
        ])
        #expect(gitMounts.map(\.destination) == gitMounts.map(\.source.path))
        #expect(gitMounts.allSatisfy { $0.access == .readOnly })
    }

    @Test
    func gitMountsAreWritableOnRequest() async throws {
        try await fixture.git("init", "-q", ".", directory: fixture.workspace)
        let spec = try await prepare { $0.gitAccessMode = .write }
        let gitDirectory = fixture.workspace.appendingPathComponent(".git")
        #expect(spec.mounts.last?.source.path == gitDirectory.path)
        #expect(spec.mounts.last?.access == .readWrite)
    }

    @Test
    func worktreeMountsCommonGitDirectory() async throws {
        let main = try fixture.makeDirectory("main")
        try await fixture.git("init", "-q", ".", directory: main)
        try await fixture.git(
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@t",
            "commit",
            "-q",
            "--allow-empty",
            "-m",
            "init",
            directory: main,
        )
        try FileManager.default.removeItem(at: fixture.workspace)
        try await fixture.git("worktree", "add", "-q", fixture.workspace.path, directory: main)

        let spec = try await prepare()
        #expect(spec.mounts.last?.source.path == main.appendingPathComponent(".git").path)
        #expect(spec.mounts.last?.access == .readOnly)
    }

    @Test
    func ignoresSymlinkedGitDirectories() async throws {
        let elsewhere = try fixture.makeDirectory("elsewhere")
        try await fixture.git("init", "-q", ".", directory: elsewhere)
        let nested = try fixture.makeDirectory("nested", base: fixture.workspace)
        try FileManager.default.createSymbolicLink(
            at: nested.appendingPathComponent(".git"),
            withDestinationURL: elsewhere.appendingPathComponent(".git"),
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.workspace.appendingPathComponent("linked-repo"),
            withDestinationURL: elsewhere,
        )

        let spec = try await prepare()
        #expect(spec.mounts.last?.source.path == fixture.workspace.path)
    }

    @Test
    func noGitMountsOutsideARepo() async throws {
        let spec = try await prepare()
        #expect(spec.mounts.last?.source.path == fixture.workspace.path)
    }
}
