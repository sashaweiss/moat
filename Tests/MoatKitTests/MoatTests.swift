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
        Moat.hash(of: fixture.workspace)
    }

    var claudeSettingsFile: URL {
        sessions.appendingPathComponent("\(hash)/settings.json")
    }

    func prepare(_ configure: (inout SessionOptions) -> Void = { _ in }) throws -> VMLaunchSpec {
        var options = fixture.options
        configure(&options)
        return try fixture.moat().prepare(options)
    }

    /// The (name, source path) of each skill mounted by `spec`.
    func skills(in spec: VMLaunchSpec) -> [(String, String)] {
        spec.mounts
            .filter { $0.destination.hasPrefix("/home/robot/.claude/skills/") }
            .map { (URL(fileURLWithPath: $0.destination).lastPathComponent, $0.source.path) }
    }

    @Test
    func defaults() throws {
        let spec = try prepare()
        #expect(spec.envFile == nil)
        #expect(skills(in: spec).isEmpty)
        #expect(spec.command == ["claude", "--permission-mode", "auto", "--model", "opus"])
    }

    @Test
    func resolvesWorkspaceSymlink() throws {
        let link = fixture.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.workspace)
        let spec = try prepare { $0.workspace = link.path }
        #expect(spec.workingDirectory == fixture.workspace.path)
    }

    @Test
    func workspaceMustBeADirectory() throws {
        let file = try fixture.write("", to: "file")
        #expect(throws: MoatError.notADirectory(file.path)) {
            try prepare { $0.workspace = file.path }
        }
        #expect(throws: MoatError.notADirectory("/nonexistent")) {
            try prepare { $0.workspace = "/nonexistent" }
        }
    }

    @Test
    func invalidOptionsDoNotWriteState() throws {
        #expect(throws: MoatError.self) {
            try prepare { $0.workspace = "/nonexistent" }
        }
        let moat = fixture.home.appendingPathComponent(".moat")
        #expect(!FileManager.default.fileExists(atPath: moat.path))
    }

    @Test
    func envFile() throws {
        let envFile = try fixture.write("A=1", to: "tokens.env")
        let spec = try prepare { $0.envFile = envFile.path }
        #expect(spec.envFile?.path == envFile.path)
    }

    @Test
    func envFileMustBeAFile() throws {
        let missing = fixture.root.appendingPathComponent("missing.env").path
        #expect(throws: MoatError.notAFile(missing)) {
            try prepare { $0.envFile = missing }
        }
        #expect(throws: MoatError.notAFile(fixture.workspace.path)) {
            try prepare { $0.envFile = fixture.workspace.path }
        }
    }

    @Test
    func hostSkillsAreFiltered() throws {
        let hostSkills = try fixture.makeDirectory(".claude/skills", in: fixture.home)
        try fixture.makeDirectory("zeta", in: hostSkills)
        try fixture.makeDirectory("alpha", in: hostSkills)
        try fixture.makeDirectory(".hidden", in: hostSkills)
        try fixture.write("", to: "not-a-skill.md", in: hostSkills)
        let linkedSkill = try fixture.makeDirectory("elsewhere/linked")
        try FileManager.default.createSymbolicLink(
            at: hostSkills.appendingPathComponent("linked"),
            withDestinationURL: linkedSkill,
        )

        let skills = Dictionary(uniqueKeysWithValues: skills(in: try prepare()))
        #expect(skills.keys.sorted() == ["alpha", "linked", "zeta"])
        #expect(skills["linked"] == linkedSkill.path)
    }

    @Test
    func additionalSkills() throws {
        try fixture.makeDirectory(".claude/skills/host", in: fixture.home)
        let extra = try fixture.makeDirectory("extra")
        let skills = skills(in: try prepare { $0.additionalSkills = [extra.path] })
        #expect(skills.map(\.0) == ["host", "extra"])
        #expect(skills[1].1 == extra.path)
    }

    @Test
    func additionalSkillMustBeADirectory() throws {
        let missing = fixture.root.appendingPathComponent("missing").path
        #expect(throws: MoatError.notADirectory(missing)) {
            try prepare { $0.additionalSkills = [missing] }
        }
    }

    @Test
    func duplicateSkill() throws {
        try fixture.makeDirectory(".claude/skills/dupe", in: fixture.home)
        let other = try fixture.makeDirectory("other/dupe")
        #expect(throws: MoatError.duplicateSkill("dupe")) {
            try prepare { $0.additionalSkills = [other.path] }
        }
    }

    @Test
    func hashMatchesPythonImplementation() {
        #expect(Moat.hash(of: URL(fileURLWithPath: "/Users/sasha/dev/moat")) == "efb554af842e01ce")
    }

    @Test
    func spec() throws {
        let spec = try prepare {
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
    func mounts() throws {
        try fixture.makeDirectory(".claude/skills/skill", in: fixture.home)
        let spec = try prepare()
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
    func writesState() throws {
        _ = try prepare()
        let fileManager = FileManager.default
        let credentials = fixture.home.appendingPathComponent(".moat/credentials.json")
        #expect(fileManager.fileExists(atPath: credentials.path))
        #expect(sessions.appendingPathComponent(hash).isDirectory)
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
    func preservesExistingState() throws {
        let credentials = try fixture.write(
            "secret",
            to: ".moat/credentials.json",
            in: fixture.home,
        )
        let claudeJSON = try fixture.write("{}", to: "\(hash).claude.json", in: sessions)
        let settings = try fixture.write("{}", to: "\(hash)/settings.json", in: sessions)
        _ = try prepare()
        #expect(try fixture.read(credentials) == "secret")
        #expect(try fixture.read(claudeJSON) == "{}")
        #expect(try fixture.read(settings) == "{}")
    }

    @Test
    func seedsClaudeSettingsFromHost() throws {
        try fixture.write(
            #"{"theme": "dark", "nested": {"a": [1, true]}}"#,
            to: ".claude/settings.json",
            in: fixture.home,
        )
        _ = try prepare()
        let settings = try fixture.readJSON(claudeSettingsFile)
        #expect(settings["theme"] as? String == "dark")
        #expect(settings["autoMemoryDirectory"] as? String == "~/.claude/memory")
        #expect((settings["nested"] as? NSDictionary)?["a"] as? NSArray == [1, true])
    }

    @Test
    func doesNotSeedClaudeSettingsWhenDisabled() throws {
        try fixture.write(#"{"theme": "dark"}"#, to: ".claude/settings.json", in: fixture.home)
        _ = try prepare { $0.seedsClaudeSettings = false }
        let settings = try fixture.readJSON(claudeSettingsFile)
        #expect(settings == ["autoMemoryDirectory": "~/.claude/memory"])
    }

    @Test
    func invalidHostClaudeSettings() throws {
        let url = try fixture.write("[]", to: ".claude/settings.json", in: fixture.home)
        #expect(throws: MoatError.invalidSettingsFile(url.path)) {
            try prepare()
        }
        try fixture.write("{", to: ".claude/settings.json", in: fixture.home)
        #expect(throws: MoatError.invalidSettingsFile(url.path)) {
            try prepare()
        }
    }

    @Test
    func claudeMD() throws {
        let prologue = claudePrologue
        #expect(prologue.hasPrefix("# Prologue"))
        let claudeMD = sessions.appendingPathComponent("\(hash).CLAUDE.md")

        _ = try prepare()
        #expect(try fixture.read(claudeMD) == prologue)

        // Rewritten every time, to pick up changes to the host's CLAUDE.md.
        try fixture.write("host instructions", to: ".claude/CLAUDE.md", in: fixture.home)
        _ = try prepare()
        #expect(try fixture.read(claudeMD) == prologue + "\n\nhost instructions")
    }

    @Test
    func gitMountsAreReadOnlyByDefault() throws {
        try fixture.git("init", "-q", ".", in: fixture.workspace)
        let nested = try fixture.makeDirectory("nested", in: fixture.workspace)
        try fixture.git("init", "-q", ".", in: nested)

        let spec = try prepare()
        let gitMounts = spec.mounts.suffix(2)
        #expect(gitMounts.map(\.source.path) == [
            fixture.workspace.appendingPathComponent(".git").path,
            nested.appendingPathComponent(".git").path,
        ])
        #expect(gitMounts.map(\.destination) == gitMounts.map(\.source.path))
        #expect(gitMounts.allSatisfy { $0.access == .readOnly })
    }

    @Test
    func gitMountsAreWritableOnRequest() throws {
        try fixture.git("init", "-q", ".", in: fixture.workspace)
        let spec = try prepare { $0.gitAccessMode = .write }
        let gitDirectory = fixture.workspace.appendingPathComponent(".git")
        #expect(spec.mounts.last?.source.path == gitDirectory.path)
        #expect(spec.mounts.last?.access == .readWrite)
    }

    @Test
    func worktreeMountsCommonGitDirectory() throws {
        let main = try fixture.makeDirectory("main")
        try fixture.git("init", "-q", ".", in: main)
        try fixture.git(
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@t",
            "commit",
            "-q",
            "--allow-empty",
            "-m",
            "init",
            in: main,
        )
        try FileManager.default.removeItem(at: fixture.workspace)
        try fixture.git("worktree", "add", "-q", fixture.workspace.path, in: main)

        let spec = try prepare()
        #expect(spec.mounts.last?.source.path == main.appendingPathComponent(".git").path)
        #expect(spec.mounts.last?.access == .readOnly)
    }

    @Test
    func ignoresSymlinkedGitDirectories() throws {
        let elsewhere = try fixture.makeDirectory("elsewhere")
        try fixture.git("init", "-q", ".", in: elsewhere)
        let nested = try fixture.makeDirectory("nested", in: fixture.workspace)
        try FileManager.default.createSymbolicLink(
            at: nested.appendingPathComponent(".git"),
            withDestinationURL: elsewhere.appendingPathComponent(".git"),
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.workspace.appendingPathComponent("linked-repo"),
            withDestinationURL: elsewhere,
        )

        let spec = try prepare()
        #expect(spec.mounts.last?.source.path == fixture.workspace.path)
    }

    @Test
    func noGitMountsOutsideARepo() throws {
        let spec = try prepare()
        #expect(spec.mounts.last?.source.path == fixture.workspace.path)
    }
}
