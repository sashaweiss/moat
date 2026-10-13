import Crypto
import Foundation

/// Prepares moat sessions.
public struct Moat {
    public var environment: MoatEnvironment

    static let image = "moat:latest"
    static let user = "robot"
    static let vmHomeDirectory = "/home/robot"

    public init(environment: MoatEnvironment = MoatEnvironment()) {
        self.environment = environment
    }

    /// Loads the user's `~/.moat/settings.json`.
    public func loadSettings() throws -> MoatSettings {
        try MoatSettings.load(from: environment.settingsFile)
    }

    /// Validates `options`, then prepares moat's state on disk for them,
    /// returning a spec to launch the session.
    public func prepare(_ options: SessionOptions) throws -> VMLaunchSpec {
        let fileManager = FileManager.default

        guard Filesystem.isDirectory(URL(fileURLWithPath: options.workspace)) else {
            throw MoatError.notADirectory(options.workspace)
        }
        let workspace = Filesystem.resolveSymlinks(URL(fileURLWithPath: options.workspace))

        var envFile: URL?
        if let envFileOption = options.envFile {
            let url = URL(fileURLWithPath: NSString(string: envFileOption).expandingTildeInPath)
            guard Filesystem.isFile(url) else {
                throw MoatError.notAFile(envFileOption)
            }
            envFile = url
        }

        // Mount skills individually, keyed by name, so symlinked skills work.
        var skills: [(name: String, directory: URL)] = []
        let hostSkillsDirectory = environment.claudeDirectory.appendingPathComponent("skills")
        if Filesystem.isDirectory(hostSkillsDirectory) {
            let contents = try fileManager.contentsOfDirectory(
                at: hostSkillsDirectory,
                includingPropertiesForKeys: nil,
            )
            for skill in contents {
                guard Filesystem.isDirectory(skill), !skill.lastPathComponent.hasPrefix(".") else {
                    continue
                }
                skills.append((skill.lastPathComponent, Filesystem.resolveSymlinks(skill)))
            }
        }
        for skillOption in options.additionalSkills {
            let url = URL(fileURLWithPath: NSString(string: skillOption).expandingTildeInPath)
            guard Filesystem.isDirectory(url) else {
                throw MoatError.notADirectory(skillOption)
            }
            let skill = Filesystem.resolveSymlinks(url)
            guard !skills.contains(where: { $0.name == skill.lastPathComponent }) else {
                throw MoatError.duplicateSkill(skill.lastPathComponent)
            }
            skills.append((skill.lastPathComponent, skill))
        }

        let claudeDirectory = environment.claudeDirectory
        let sessionsDirectory = environment.sessionsDirectory
        try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let credentialsFile = environment.credentialsFile
        if !fileManager.fileExists(atPath: credentialsFile.path) {
            try Data().write(to: credentialsFile)
        }

        // Prepare a per-workspace (keyed by a hash of the directory path)
        // directory where we can save the ~/.claude directories from the VM
        // durably on the host, under ~/.moat/sessions. We'll mount this into
        // the VM, so Claude has context from and can resume previous sessions
        // in this workspace.
        let workspaceHash = Self.hash(of: workspace)
        let stateDirectory = sessionsDirectory.appendingPathComponent(workspaceHash)
        try fileManager.createDirectory(at: stateDirectory, withIntermediateDirectories: true)

        // We'll mount the workspace in the VM at the same absolute path as on
        // the host, and run Claude from there. We'll also mount the
        // workspace's "common git dir" (either .git/, or if we're a worktree
        // then the .git/ of the main worktree) at its absolute path as on the
        // host.
        //
        // This ensures that git operations in the workspace work as they do on
        // the host, without having to worry about the paths a worktree (or any
        // submodules, or submodules in a worktree) might expect for .git
        // contents.
        //
        // Also apply the git mount mode to any nested repos in the workspace
        // (e.g., independent clones), since they'd otherwise be writable via
        // the workspace mount.
        var gitDirectories: [URL] = try Git.commonDirectory(for: workspace).map { [$0] } ?? []
        for nested in try Git.directories(under: workspace) {
            if !gitDirectories.contains(where: { $0.path == nested.path }) {
                gitDirectories.append(nested)
            }
        }

        // For first-time workspaces, write a dummy .claude.json to populate
        // some default settings (silence FRE prompts). We'll store it in the
        // sessions directory, then mount it into the VM at ~/.claude.json.
        let claudeJSONFile = sessionsDirectory.appendingPathComponent(
            "\(workspaceHash).claude.json",
        )
        if !fileManager.fileExists(atPath: claudeJSONFile.path) {
            let claudeJSON: [String: Any] = [
                "hasCompletedOnboarding": true,
                "hasSeenAutoModeEntryWarning": true,
                "projects": [
                    workspace.path: [
                        "hasTrustDialogAccepted": true,
                    ],
                ],
            ]
            try Self.writeJSON(claudeJSON, to: claudeJSONFile)
        }

        // Likewise, seed a settings.json into the state directory, which is
        // mounted at ~/.claude. Use the host's ~/.claude/settings.json if
        // present.
        let claudeSettingsFile = stateDirectory.appendingPathComponent("settings.json")
        if !fileManager.fileExists(atPath: claudeSettingsFile.path) {
            var claudeSettings: [String: Any] = [:]
            let hostClaudeSettingsFile = claudeDirectory.appendingPathComponent("settings.json")
            if
                options.seedsClaudeSettings,
                fileManager.fileExists(atPath: hostClaudeSettingsFile.path)
            {
                let data = try Data(contentsOf: hostClaudeSettingsFile)
                let object = try? JSONSerialization.jsonObject(with: data)
                guard let hostClaudeSettings = object as? [String: Any] else {
                    throw MoatError.invalidSettingsFile(hostClaudeSettingsFile.path)
                }
                claudeSettings = hostClaudeSettings
            }
            // Always set autoMemoryDirectory, since that's part of the moat
            // integration.
            claudeSettings["autoMemoryDirectory"] = "~/.claude/memory"
            try Self.writeJSON(claudeSettings, to: claudeSettingsFile)
        }

        // Populate the VM's CLAUDE.md with a prefix describing the moat
        // environment, followed by the contents of the host's
        // ~/.claude/CLAUDE.md.
        var claudeMD = claudePrologue
        let hostClaudeMDFile = claudeDirectory.appendingPathComponent("CLAUDE.md")
        if Filesystem.isFile(hostClaudeMDFile) {
            claudeMD += "\n\n" + (try String(contentsOf: hostClaudeMDFile, encoding: .utf8))
        }
        let claudeMDFile = sessionsDirectory.appendingPathComponent("\(workspaceHash).CLAUDE.md")
        try claudeMD.write(to: claudeMDFile, atomically: false, encoding: .utf8)

        // For debugging purposes, write a pointer from the workspace hash back
        // to the workspace itself. This isn't mounted into the VM.
        let pointerFile = sessionsDirectory.appendingPathComponent("\(workspaceHash).pointer")
        try workspace.path.write(to: pointerFile, atomically: false, encoding: .utf8)

        let vmClaudeDirectory = "\(Self.vmHomeDirectory)/.claude"
        var mounts = [
            Mount(
                source: stateDirectory,
                destination: vmClaudeDirectory,
                access: .readWrite,
            ),
            Mount(
                source: credentialsFile,
                destination: "\(vmClaudeDirectory)/.credentials.json",
                access: .readWrite,
            ),
            Mount(
                source: claudeJSONFile,
                destination: "\(Self.vmHomeDirectory)/.claude.json",
                access: .readWrite,
            ),
            Mount(
                source: claudeMDFile,
                destination: "\(vmClaudeDirectory)/CLAUDE.md",
                access: .readOnly,
            ),
        ]

        // Skills are read-only, so any .git/ directories in them are too.
        for skill in skills {
            mounts.append(Mount(
                source: skill.directory,
                destination: "\(vmClaudeDirectory)/skills/\(skill.name)",
                access: .readOnly,
            ))
        }

        // We mount the git dir read-only by default so that all changes made
        // inside the moat session are obvious from the host (no possibility
        // for commits, ignoring, etc.). However, if specifically requested
        // we'll allow git dir write access.
        //
        // Mounts nested inside other mounts must come after their parent.
        mounts.append(Mount(source: workspace, destination: workspace.path, access: .readWrite))
        let gitAccess: Mount.Access = switch options.gitAccessMode {
        case .read: .readOnly
        case .write: .readWrite
        }
        for gitDirectory in gitDirectories {
            mounts.append(Mount(
                source: gitDirectory,
                destination: gitDirectory.path,
                access: gitAccess,
            ))
        }

        return VMLaunchSpec(
            name: "moat.\(workspace.lastPathComponent)",
            image: Self.image,
            cpus: 2,
            memory: "4G",
            user: Self.user,
            workingDirectory: workspace.path,
            envFile: envFile,
            mounts: mounts,
            command: [
                "claude",
                "--permission-mode",
                options.permissionMode,
                "--model",
                options.model,
            ] + options.claudeArguments,
        )
    }

    /// The key for a workspace's state under `~/.moat/sessions`.
    static func hash(of workspace: URL) -> String {
        SHA256.hash(data: Data(workspace.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(16)
            .description
    }

    static func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes],
        )
        try data.write(to: url)
    }
}
