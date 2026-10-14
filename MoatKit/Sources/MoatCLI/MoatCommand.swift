import ArgumentParser
import Foundation
import MoatKit

extension GitAccessMode: ExpressibleByArgument {}

@main
struct MoatCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "moat",
            abstract: "Runs Claude Code in a sandboxed VM with the given <workspace> directory mounted.",
            discussion: """
            Any additional arguments are forwarded to `claude` inside the container. \
            Defaults may be set in \(MoatEnvironment().settingsFile.path).
            """,
        )
    }

    @Argument(help: "directory to mount as the workspace in the container")
    var workspace: String

    @Option(help: "Claude Code permission mode (default: auto)")
    var permissionMode: String?

    @Option(
        name: .customLong("add-skill"),
        help: ArgumentHelp(
            "skill directory to mount into the container, in addition to the host's ~/.claude/skills",
            valueName: "dir",
        ),
    )
    var additionalSkills: [String] = []

    @Option(help: "mount the git directory read-only or read-write (default: read)")
    var gitAccessMode: GitAccessMode?

    @Option(help: ArgumentHelp(
        "file of KEY=VALUE secrets to inject as environment variables",
        valueName: "path",
    ))
    var envFile: String?

    @Option(help: "Claude model for the session; defaults to the latest Opus (default: opus)")
    var model: String?

    @Flag(help: "don't seed new sessions with the host's ~/.claude/settings.json")
    var noClaudeSettings = false

    @Argument(parsing: .allUnrecognized, help: .hidden)
    var claudeArguments: [String] = []

    func run() async throws {
        let moat = Moat()
        let options = options(settings: try moat.loadSettings())
        let spec = try await moat.prepare(options)

        let workspaceName = URL(fileURLWithPath: spec.workingDirectory).lastPathComponent
        print("moat: run claude in \"\(workspaceName)\" with permission mode \"\(options.permissionMode)\"?")
        if options.gitAccessMode == .write {
            print("WARNING: claude will have write access to git!")
        }
        print("[y/n] ", terminator: "")
        fflush(nil)
        guard let answer = readLine() else {
            print()
            throw ExitCode.failure
        }
        guard answer.trimmingCharacters(in: .whitespaces).lowercased() == "y" else {
            throw ExitCode.failure
        }

        try await Container.startSystemIfNeeded()

        // Replace this process with `container`, so it owns the terminal
        // (a `Process` child isn't in the terminal's foreground process
        // group, so it can't read keyboard input).
        let command = Container.startCommand(spec: spec)
        execvp(command[0], command.map { strdup($0) } + [nil])
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ENOENT)
    }

    /// Returns session options from `settings`, overridden by command-line
    /// arguments.
    func options(settings: MoatSettings) -> SessionOptions {
        var options = SessionOptions(workspace: workspace)
        settings.apply(options: &options)
        options.additionalSkills += additionalSkills
        if let permissionMode {
            options.permissionMode = permissionMode
        }
        if let gitAccessMode {
            options.gitAccessMode = gitAccessMode
        }
        if let envFile {
            options.envFile = envFile
        }
        if let model {
            options.model = model
        }
        if noClaudeSettings {
            options.seedsClaudeSettings = false
        }
        options.claudeArguments = claudeArguments
        return options
    }
}
