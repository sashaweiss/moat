import Foundation
import Subprocess

/// Runs agent VMs using Apple's `container` tool.
public enum Container {
    /// Starts `container`'s daemon if it isn't running yet.
    public static func startSystemIfNeeded() async throws {
        let systemStatus = try await run(
            .name("container"),
            arguments: ["system", "status"],
            output: .discarded,
        )
        if systemStatus.terminationStatus.isSuccess {
            return
        }
        // This may prompt (e.g., to install a kernel), so give it our terminal, if any.
        let start = try await run(
            .name("container"),
            arguments: ["system", "start"],
            input: .currentStandardInput,
            output: .currentStandardOutput,
            error: .currentStandardError,
        )
        if !start.terminationStatus.isSuccess {
            throw MoatError.commandFailed(
                ["container", "system", "start"],
                status: start.terminationStatus,
            )
        }
    }

    /// Returns the command (starting with `container`) that stops `spec`'s VM.
    public static func stopCommand(spec: VMLaunchSpec) -> [String] {
        ["container", "stop", spec.name]
    }

    /// Returns the command (starting with `container`) that launches `spec`
    /// interactively in the current terminal.
    public static func startCommand(spec: VMLaunchSpec) -> [String] {
        var command = [
            "container",
            "run",
            "-it",
            "--rm",
            "--name",
            spec.name,
            "--cpus",
            String(spec.cpus),
            "--memory",
            spec.memory,
            "-u",
            spec.user,
            "-w",
            spec.workingDirectory,
        ]
        if let envFile = spec.envFile {
            command += ["--env-file", envFile.path]
        }
        for mount in spec.mounts {
            let mode = switch mount.access {
            case .readOnly: "ro"
            case .readWrite: "rw"
            }
            command += ["-v", "\(mount.source.path):\(mount.destination):\(mode)"]
        }
        command.append(spec.image)
        command += spec.command
        return command
    }
}
