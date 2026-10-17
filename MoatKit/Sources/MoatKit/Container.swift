import Foundation

/// Runs agent VMs using Apple's `container` tool.
public enum Container {

    /// Assembles a `HostCommands` backed by `container`.
    public static func hostCommands(settings: HostSettings) -> HostCommands {
        let executable = settings.containerPath
        return HostCommands(
            checkSystem: [executable, "system", "status"],
            startSystem: [executable, "system", "start"],
            startVM: { spec in startCommand(spec: spec, executable: executable) },
            stopVM: { spec in stopCommand(spec: spec, executable: executable) },
            listRunningVMs: [executable, "list", "--quiet"],
            listImages: [executable, "image", "list", "--format", "json"],
            gitPath: settings.gitPath,
        )
    }

    /// Returns the command (starting with `executable`) that stops `spec`'s
    /// VM.
    static func stopCommand(spec: VMLaunchSpec, executable: String) -> [String] {
        [executable, "stop", spec.name]
    }

    /// Returns the command (starting with `executable`) that launches `spec`
    /// interactively in the current terminal.
    static func startCommand(
        spec: VMLaunchSpec,
        executable: String,
    ) -> [String] {
        var command = [
            executable,
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
