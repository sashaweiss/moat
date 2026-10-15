import Foundation

/// Runs agent VMs using Apple's `container` tool.
public enum Container {
    /// The commands a `SessionManager` uses to run VMs with `container`.
    public static let sessionCommands = SessionCommands(
        checkSystem: ["container", "system", "status"],
        startSystem: ["container", "system", "start"],
        start: { spec in startCommand(spec: spec) },
        stop: { spec in stopCommand(spec: spec) },
    )

    /// Returns the command (starting with `container`) that stops `spec`'s VM.
    static func stopCommand(spec: VMLaunchSpec) -> [String] {
        ["container", "stop", spec.name]
    }

    /// Returns the command (starting with `container`) that launches `spec`
    /// interactively in the current terminal.
    static func startCommand(spec: VMLaunchSpec) -> [String] {
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
