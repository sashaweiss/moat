import ArgumentParser
import CMoatKit
import Foundation
import MoatKit
#if canImport(System)
import System
#else
import SystemPackage
#endif

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

    @Option(help: "number of CPUs for the VM (default: 2)")
    var cpus: Int?

    @Option(help: "memory for the VM, e.g. 8G (default: 4G)")
    var memory: String?

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

        let state = try await Self.runSession(spec: spec)
        switch state {
        case .exited(let code):
            throw ExitCode(code)
        case .signaled(let signal):
            // As shells report it.
            throw ExitCode(128 + signal)
        case .failed(let description):
            print("moat: couldn't run the VM: \(description)")
            throw ExitCode.failure
        case .running, .stopping:
            preconditionFailure("The session should have exited.")
        }
    }

    /// Runs `spec`'s VM in a `Session` attached to this process's terminal,
    /// and returns the session's state once it exits.
    @MainActor
    static func runSession(spec: VMLaunchSpec) async throws -> Session.State {
        let stdin = FileDescriptor.standardInput
        let stdout = FileDescriptor.standardOutput

        // System's `FileDescriptor` has no terminal APIs, so these take its
        // raw value.
        guard isatty(stdin.rawValue) == 1, isatty(stdout.rawValue) == 1 else {
            throw ValidationError("moat must be run in a terminal.")
        }
        let session = try Session.start(
            spec: spec,
            startCommand: Container.startCommand(spec: spec),
            stopCommand: Container.stopCommand(spec: spec),
            size: try terminalSize(terminal: stdin),
        )

        // Ignore SIGWINCH for ourselves. Instead, handle it by telling the
        // session to resize itself.
        signal(SIGWINCH, SIG_IGN)
        let windowSizeChanges = DispatchSource.makeSignalSource(
            signal: SIGWINCH,
            queue: .main,
        )
        windowSizeChanges.setEventHandler {
            MainActor.assumeIsolated {
                if let size = try? terminalSize(terminal: stdin) {
                    session.resize(size)
                }
            }
        }
        windowSizeChanges.resume()
        defer {
            windowSizeChanges.cancel()
        }

        // Get our stdin's attributes, then set "raw" mode on them and write
        // them back to stdin; i.e., set our stdin to "raw" mode. That lets
        // keystrokes like Ctrl-C pass through to the VM without our terminal
        // interpreting them.
        var originalAttributes = termios()
        tcgetattr(stdin.rawValue, &originalAttributes)
        var rawAttributes = originalAttributes
        cfmakeraw(&rawAttributes)
        tcsetattr(stdin.rawValue, TCSANOW, &rawAttributes)
        defer {
            tcsetattr(stdin.rawValue, TCSANOW, &originalAttributes)
        }

        // Reading blocks until there's input, so it gets its own thread.
        Thread.detachNewThread {
            relayInput(input: stdin, session: session)
        }

        for try await chunk in session.outputStream {
            try stdout.writeAll(chunk)
        }
        await session.waitForExit()
        return session.state
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
        if let cpus {
            options.cpus = cpus
        }
        if let memory {
            options.memory = memory
        }
        if noClaudeSettings {
            options.seedsClaudeSettings = false
        }
        options.claudeArguments = claudeArguments
        return options
    }
}

/// Returns the size of `terminal`.
private func terminalSize(terminal: FileDescriptor) throws -> TerminalSize {
    var windowSize = winsize()
    guard ioctl(terminal.rawValue, kTIOCGWINSZ, &windowSize) == 0 else {
        throw Errno(rawValue: errno)
    }
    return TerminalSize(
        columns: Int(windowSize.ws_col),
        rows: Int(windowSize.ws_row),
    )
}

/// Sends what's read from `input` to `session` until there's no more.
private func relayInput(
    input: FileDescriptor,
    session: Session,
    bufferSize: Int = 1024,
) {
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    do {
        while true {
            // Returns as soon as any bytes are available, and at most
            // `buffer.count` of them.
            let count = try buffer.withUnsafeMutableBytes { bytes in
                try input.read(into: bytes)
            }
            guard count > 0 else {
                break
            }
            session.write(buffer[..<count])
        }
    } catch {
        // Our input is gone (e.g., its terminal closed), so there's nothing
        // more to send.
    }
}
