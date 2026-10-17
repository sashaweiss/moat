import Foundation
import Subprocess

/// A command that Moat runs on the host for its output, which `parse` turns
/// into an `Output`.
public struct HostQuery<Output>: Sendable {
    public var command: [String]
    public var parse: @Sendable (Data) throws -> Output

    public init(
        command: [String],
        parse: @escaping @Sendable (Data) throws -> Output,
    ) {
        self.command = command
        self.parse = parse
    }

    /// Runs `command`, and returns its parsed output. Fails if it fails.
    func run() async throws -> Output {
        let result = try await Subprocess.run(
            .moatCommand(command),
            output: .data(limit: 1 << 24),
        )
        guard result.terminationStatus.isSuccess else {
            throw MoatError.commandFailed(
                command,
                status: result.terminationStatus,
            )
        }
        return try parse(result.standardOutput)
    }
}

// MARK: -

/// Commands Moat needs to run on the host.
public struct HostCommands: Sendable {
    /// Succeeds if the tool's background system, which runs VMs, is running.
    public var checkSystem: [String]
    /// Starts the tool's background system. May prompt on the session's
    /// terminal (e.g., to install a component).
    public var startSystem: [String]
    /// Returns the command that runs a VM on the terminal it's started with,
    /// until the VM exits.
    public var startVM: @Sendable (VMLaunchSpec) -> [String]
    /// Returns the command that stops a VM, causing `startVM` to exit.
    public var stopVM: @Sendable (VMLaunchSpec) -> [String]
    /// Lists the names of the running VMs.
    public var listRunningVMs: HostQuery<Set<String>>
    /// Lists the names of the images, like `moat:base`.
    public var listImages: HostQuery<[String]>

    /// Path to a `git` executable.
    public var gitPath: String

    public init(
        checkSystem: [String],
        startSystem: [String],
        startVM: @escaping @Sendable (VMLaunchSpec) -> [String],
        stopVM: @escaping @Sendable (VMLaunchSpec) -> [String],
        listRunningVMs: HostQuery<Set<String>>,
        listImages: HostQuery<[String]>,
        gitPath: String,
    ) {
        self.checkSystem = checkSystem
        self.startSystem = startSystem
        self.startVM = startVM
        self.stopVM = stopVM
        self.listRunningVMs = listRunningVMs
        self.listImages = listImages
        self.gitPath = gitPath
    }
}
