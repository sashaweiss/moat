import Foundation
import Testing
@testable import MoatKit

struct GuestVMTests {
    let fixture: Fixture

    init() throws {
        fixture = try Fixture()
    }

    var sessions: URL {
        fixture.home.appendingPathComponent(".moat/sessions")
    }

    var workspace: Workspace {
        Workspace(folder: fixture.workspace)
    }

    var hash: String {
        workspace.hash
    }

    var metadataFile: URL {
        sessions.appendingPathComponent("\(hash).metadata.json")
    }

    var claudeSettingsFile: URL {
        sessions.appendingPathComponent("\(hash)/settings.json")
    }

    /// Prepares `workspace` (by default, the fixture's) with default options
    /// changed by `configure`.
    func prepare(
        workspace: Workspace? = nil,
        claudeArguments: [String] = [],
        _ configure: (inout SessionOptions) -> Void = { _ in },
    ) async throws -> VMLaunchSpec {
        var options = SessionOptions()
        configure(&options)
        return try await fixture.guestVM().prepare(
            workspace: workspace ?? self.workspace,
            options: options,
            claudeArguments: claudeArguments,
            gitPath: "/usr/bin/git",
        )
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
        #expect(spec.cpus == 2)
        #expect(spec.memory == "4G")
        #expect(spec.image == "moat:base")
        #expect(spec.envFile == nil)
        #expect(skills(spec: spec).isEmpty)
        #expect(spec.command == [
            "sh",
            "-c",
            GuestVM.launchScript,
            "moat-launch",
            "--permission-mode",
            "auto",
            "--model",
            "opus",
        ])
    }

    @Test
    func usesOptionsImage() async throws {
        let spec = try await prepare { $0.image = "moat:swift" }
        #expect(spec.image == "moat:swift")
    }

    @Test
    func resolvesWorkspaceSymlink() async throws {
        let link = fixture.root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.workspace)
        let spec = try await prepare(workspace: Workspace(folder: link))
        #expect(spec.workingDirectory == fixture.workspace.path)
    }

    @Test
    func workspaceMustBeADirectory() async throws {
        let file = try fixture.write("", path: "file")
        await #expect(throws: MoatError.notADirectory(file.path)) {
            try await prepare(workspace: Workspace(folder: file))
        }
        await #expect(throws: MoatError.notADirectory("/nonexistent")) {
            try await prepare(
                workspace: Workspace(folder: URL(fileURLWithPath: "/nonexistent")),
            )
        }
    }

    @Test
    func invalidOptionsDoNotWriteState() async throws {
        await #expect(throws: MoatError.self) {
            try await prepare(
                workspace: Workspace(folder: URL(fileURLWithPath: "/nonexistent")),
            )
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
    func hostSkillsAreSortedAndUnresolved() throws {
        let hostSkills = try fixture.makeDirectory(".claude/skills", base: fixture.home)
        try fixture.makeDirectory("zeta", base: hostSkills)
        try fixture.makeDirectory(".hidden", base: hostSkills)
        try fixture.write("", path: "not-a-skill.md", base: hostSkills)
        let linkedSkill = try fixture.makeDirectory("elsewhere/linked")
        let link = hostSkills.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: linkedSkill)

        let skills = try fixture.guestVM().hostSkills()
        #expect(skills.map(\.lastPathComponent) == ["linked", "zeta"])
        #expect(skills[0].path == link.path)
    }

    @Test
    func noHostSkillsDirectory() throws {
        #expect(try fixture.guestVM().hostSkills().isEmpty)
    }

    @Test
    func addSkills() async throws {
        try fixture.makeDirectory(".claude/skills/host", base: fixture.home)
        let extra = try fixture.makeDirectory("extra")
        let skills = skills(spec: try await prepare { $0.addSkills = [extra.path] })
        #expect(skills.map(\.0) == ["host", "extra"])
        #expect(skills[1].1 == extra.path)
    }

    @Test
    func addSkillMustBeADirectory() async throws {
        let missing = fixture.root.appendingPathComponent("missing").path
        await #expect(throws: MoatError.notADirectory(missing)) {
            try await prepare { $0.addSkills = [missing] }
        }
    }

    @Test
    func duplicateSkill() async throws {
        try fixture.makeDirectory(".claude/skills/dupe", base: fixture.home)
        let other = try fixture.makeDirectory("other/dupe")
        await #expect(throws: MoatError.duplicateSkill("dupe")) {
            try await prepare { $0.addSkills = [other.path] }
        }
    }

    @Test
    func addWorkspaces() async throws {
        let extra = try fixture.makeDirectory("extra")
        try fixture.makeDirectory("extra/.git")
        let spec = try await prepare(claudeArguments: ["--resume"]) {
            $0.addWorkspaces = [extra.path]
        }
        let extraGit = extra.appendingPathComponent(".git")
        #expect(spec.mounts.suffix(3).map(\.source.path) == [
            extra.path,
            fixture.workspace.path,
            extraGit.path,
        ])
        #expect(spec.mounts.suffix(3).map(\.destination) == [
            extra.path,
            fixture.workspace.path,
            extraGit.path,
        ])
        #expect(spec.mounts.suffix(3).map(\.access) == [
            .readWrite,
            .readWrite,
            .readOnly,
        ])
        #expect(spec.workingDirectory == fixture.workspace.path)
        #expect(spec.command.suffix(3) == ["--add-dir", extra.path, "--resume"])
    }

    @Test
    func addWorkspaceMustBeADirectory() async throws {
        let missing = fixture.root.appendingPathComponent("missing").path
        await #expect(throws: MoatError.notADirectory(missing)) {
            try await prepare { $0.addWorkspaces = [missing] }
        }
    }

    @Test
    func addWorkspacesSkipsDuplicates() async throws {
        let extra = try fixture.makeDirectory("extra")
        let spec = try await prepare {
            $0.addWorkspaces = [fixture.workspace.path, extra.path, extra.path]
        }
        let workspaceMounts = spec.mounts.filter { !$0.destination.hasPrefix("/home/robot") }
        #expect(workspaceMounts.map(\.destination) == [extra.path, fixture.workspace.path])
        #expect(spec.command.filter { $0 == "--add-dir" }.count == 1)
    }

    @Test
    func vmNameReplacesDisallowedCharacters() {
        let workspace = Workspace(
            folder: URL(fileURLWithPath: "/projects/my.café_app"),
        )
        #expect(workspace.vmName == "moat.my-caf-_app.\(workspace.hash)")
    }

    @Test
    func spec() async throws {
        let spec = try await prepare(claudeArguments: ["--resume", "-c"]) {
            $0.permissionMode = "plan"
            $0.model = "sonnet"
            $0.cpus = 4
            $0.memory = "8G"
        }
        #expect(spec.name == "moat.workspace.\(hash)")
        #expect(spec.image == "moat:base")
        #expect(spec.cpus == 4)
        #expect(spec.memory == "8G")
        #expect(spec.user == "robot")
        #expect(spec.workingDirectory == fixture.workspace.path)
        #expect(spec.envFile == nil)
        #expect(spec.command == [
            "sh",
            "-c",
            GuestVM.launchScript,
            "moat-launch",
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
        #expect(try SessionMetadata.load(file: metadataFile) == SessionMetadata(
            workspace: workspace,
            name: "workspace",
        ))

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
        _ = try await prepare()
        #expect(try fixture.read(credentials) == "secret")
        #expect(try fixture.read(claudeJSON) == "{}")
    }

    @Test
    func metadataKeepsName() async throws {
        _ = try await prepare()
        var metadata = try SessionMetadata.load(file: metadataFile)
        metadata.name = "renamed"
        try metadata.write(file: metadataFile)

        _ = try await prepare()
        #expect(try SessionMetadata.load(file: metadataFile).name == "renamed")
    }

    @Test
    func migratePointerSeedsMetadata() throws {
        let pointerFile = try fixture.write(
            fixture.workspace.path,
            path: "\(hash).pointer",
            base: sessions,
        )
        try fixture.guestVM().migratePointer(file: pointerFile)

        #expect(try SessionMetadata.load(file: metadataFile) == SessionMetadata(
            workspace: workspace,
            name: "workspace",
        ))
        #expect(!FileManager.default.fileExists(atPath: pointerFile.path))
    }

    @Test
    func migratePointerKeepsExistingMetadata() throws {
        try fixture.makeDirectory(".moat/sessions", base: fixture.home)
        let existing = SessionMetadata(
            workspace: workspace,
            name: "renamed",
        )
        try existing.write(file: metadataFile)
        let pointerFile = try fixture.write(
            fixture.workspace.path,
            path: "\(hash).pointer",
            base: sessions,
        )
        try fixture.guestVM().migratePointer(file: pointerFile)

        #expect(try SessionMetadata.load(file: metadataFile) == existing)
        #expect(!FileManager.default.fileExists(atPath: pointerFile.path))
    }

    @Test
    func prepareMigratesOnlyItsOwnPointer() async throws {
        let pointerFile = try fixture.write(
            fixture.workspace.path,
            path: "\(hash).pointer",
            base: sessions,
        )
        let other = try fixture.makeDirectory("other")
        let otherHash = Workspace(folder: other).hash
        let otherPointerFile = try fixture.write(
            other.path,
            path: "\(otherHash).pointer",
            base: sessions,
        )
        _ = try await prepare()

        #expect(!FileManager.default.fileExists(atPath: pointerFile.path))
        #expect(try fixture.read(otherPointerFile) == other.path)
        let otherMetadataFile = sessions.appendingPathComponent(
            "\(otherHash).metadata.json",
        )
        #expect(
            !FileManager.default.fileExists(atPath: otherMetadataFile.path),
        )
    }

    @Test
    func copiesClaudeSettingsFromHost() async throws {
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
    func copyingClaudeSettingsOverwritesThemOnEveryStart() async throws {
        try fixture.write(#"{"theme": "dark"}"#, path: ".claude/settings.json", base: fixture.home)
        _ = try await prepare()
        try fixture.write(
            #"{"theme": "changed in the VM"}"#,
            path: "\(hash)/settings.json",
            base: sessions,
        )
        try fixture.write(#"{"theme": "light"}"#, path: ".claude/settings.json", base: fixture.home)
        _ = try await prepare()
        let settings = try fixture.readJSON(claudeSettingsFile)
        #expect(settings["theme"] as? String == "light")
        #expect(settings["autoMemoryDirectory"] as? String == "~/.claude/memory")
    }

    @Test
    func doesNotCopyClaudeSettingsWhenDisabled() async throws {
        try fixture.write(#"{"theme": "dark"}"#, path: ".claude/settings.json", base: fixture.home)
        _ = try await prepare { $0.copyHostClaudeConfigs = false }
        let settings = try fixture.readJSON(claudeSettingsFile)
        #expect(settings == ["autoMemoryDirectory": "~/.claude/memory"])
    }

    @Test
    func keepsSessionClaudeSettingsWhenNotCopying() async throws {
        try fixture.write(#"{"theme": "dark"}"#, path: ".claude/settings.json", base: fixture.home)
        _ = try await prepare { $0.copyHostClaudeConfigs = false }
        try fixture.write(
            #"{"theme": "changed in the VM"}"#,
            path: "\(hash)/settings.json",
            base: sessions,
        )
        _ = try await prepare { $0.copyHostClaudeConfigs = false }
        let settings = try fixture.readJSON(claudeSettingsFile)
        #expect(settings == ["theme": "changed in the VM"])
    }

    @Test
    func invalidHostClaudeSettings() async throws {
        let url = try fixture.write("[]", path: ".claude/settings.json", base: fixture.home)
        let notAnObjectError = await #expect(throws: MoatError.self) {
            try await prepare()
        }
        #expect(invalidSettingsFilePath(notAnObjectError) == url.path)
        try fixture.write("{", path: ".claude/settings.json", base: fixture.home)
        let invalidJSONError = await #expect(throws: MoatError.self) {
            try await prepare()
        }
        #expect(invalidSettingsFilePath(invalidJSONError) == url.path)
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
    func claudeMDIsOnlyThePrologueWhenNotCopying() async throws {
        try fixture.write("host instructions", path: ".claude/CLAUDE.md", base: fixture.home)
        _ = try await prepare { $0.copyHostClaudeConfigs = false }
        let claudeMD = sessions.appendingPathComponent("\(hash).CLAUDE.md")
        #expect(try fixture.read(claudeMD) == claudePrologue)
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
