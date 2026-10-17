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
            listRunningVMs: HostQuery(
                command: [executable, "list", "--quiet"],
                parse: runningVMNames(output:),
            ),
            listImages: HostQuery(
                command: [executable, "image", "list", "--format", "json"],
                parse: imageNames(output:),
            ),
            gitPath: settings.gitPath,
        )
    }

    /// Returns the names of the running VMs in `output` from `container list
    /// --quiet`: one per line.
    static func runningVMNames(output: Data) -> Set<String> {
        Set(
            String(decoding: output, as: UTF8.self)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty },
        )
    }

    /// An image, as `container image list --format json` prints it.
    private struct ListedImage: Decodable {
        struct Configuration: Decodable {
            let name: String
        }

        let configuration: Configuration
    }

    /// Returns the names of the images in `output` from `container image list
    /// --format json`.
    static func imageNames(output: Data) throws -> [String] {
        try JSONDecoder()
            .decode([ListedImage].self, from: output)
            .map(\.configuration.name)
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
