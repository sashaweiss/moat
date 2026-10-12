import Foundation

/// Runs agent VMs using Apple's `container` tool.
public enum Container {
    /// Starts `container`'s daemon if it isn't running yet.
    public static func startSystemIfNeeded() throws {
        if try run(["container", "system", "status"]) != 0 {
            let start = ["container", "system", "start"]
            let status = try run(start, standardOutput: nil, standardError: nil)
            if status != 0 {
                throw MoatError.commandFailed(start, status: status)
            }
        }
    }

    /// Returns the command (starting with `container`) that launches `spec`
    /// interactively in the current terminal.
    public static func runCommand(for spec: VMLaunchSpec) -> [String] {
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
