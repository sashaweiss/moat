import Foundation

/// Prepares a description of the VM a moat session will run in.
public struct GuestVM: Sendable {
    public var environment: HostEnvironment

    static let image = "moat:latest"
    static let user = "robot"
    static let vmHomeDirectory = "/home/robot"

    public init(environment: HostEnvironment = HostEnvironment()) {
        self.environment = environment
    }

    /// Validates `workspace` and `options`, then prepares moat's state on
    /// disk for them, returning a spec to launch the session. The session runs
    /// `claude` with `claudeArguments` added.
    public func prepare(
        workspace: Workspace,
        options: SessionOptions,
        claudeArguments: [String],
    ) async throws -> VMLaunchSpec {
        let fileManager = FileManager.default

        guard Filesystem.isDirectory(workspace.url) else {
            throw MoatError.notADirectory(workspace.path)
        }

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
        for skillOption in options.addSkills {
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
        let workspaceHash = workspace.hash
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
        var gitDirectories: [URL] = []
        if
            let commonDirectory = try await Git.commonDirectory(
                workspace: workspace.url,
                gitPath: options.gitPath,
            )
        {
            gitDirectories.append(commonDirectory)
        }
        for nested in try Git.directories(root: workspace.url) {
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
                !options.noClaudeSettings,
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

        // Record the session's metadata, migrating any .pointer files from
        // earlier versions of moat.
        let pointerFile = sessionsDirectory.appendingPathComponent(
            "\(workspaceHash).pointer",
        )
        if Filesystem.isFile(pointerFile) {
            try migratePointer(file: pointerFile)
        }
        let metadataFile = environment.metadataFile(
            workspaceHash: workspaceHash,
        )
        let existingMetadata = try? SessionMetadata.load(file: metadataFile)
        let metadata = SessionMetadata(
            workspace: workspace,
            name: existingMetadata?.name ?? workspace.name,
        )
        try metadata.write(file: metadataFile)

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
        mounts.append(Mount(
            source: workspace.url,
            destination: workspace.path,
            access: .readWrite,
        ))
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
            name: workspace.vmName,
            image: Self.image,
            cpus: options.cpus,
            memory: options.memory,
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
            ] + claudeArguments,
        )
    }

    /// Migrates a `<hash>.pointer` file, which holds a session's workspace
    /// path as plain text, to `<hash>.metadata.json`. If that metadata doesn't
    /// exist yet, it's seeded from the workspace path.
    /// Either way, the `.pointer` file is removed.
    func migratePointer(file pointerFile: URL) throws {
        let path = try String(contentsOf: pointerFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = Workspace(folder: URL(fileURLWithPath: path))
        let hash = pointerFile.deletingPathExtension().lastPathComponent
        let metadataFile = environment.metadataFile(workspaceHash: hash)
        if !Filesystem.isFile(metadataFile) {
            let metadata = SessionMetadata(
                workspace: workspace,
                name: workspace.name,
            )
            try metadata.write(file: metadataFile)
        }
        try FileManager.default.removeItem(at: pointerFile)
    }

    static func writeJSON(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes],
        )
        try data.write(to: url)
    }
}
