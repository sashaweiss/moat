import Foundation
import Testing
@testable import MoatKit

struct ContainerTests {
    func spec(envFile: URL? = nil) -> VMLaunchSpec {
        VMLaunchSpec(
            name: "moat.ws",
            image: "moat:latest",
            cpus: 2,
            memory: "4G",
            user: "robot",
            workingDirectory: "/ws",
            envFile: envFile,
            mounts: [
                Mount(
                    source: URL(fileURLWithPath: "/state"),
                    destination: "/home/robot/.claude",
                    access: .readWrite,
                ),
                Mount(
                    source: URL(fileURLWithPath: "/ws/.git"),
                    destination: "/ws/.git",
                    access: .readOnly,
                ),
            ],
            command: ["claude", "--model", "opus"],
        )
    }

    @Test
    func hostCommands() {
        var settings = HostSettings()
        settings.containerPath = "/bin/container"
        settings.gitPath = "/opt/bin/git"
        let commands = Container.hostCommands(settings: settings)
        #expect(commands.checkSystem == ["/bin/container", "system", "status"])
        #expect(commands.startSystem == ["/bin/container", "system", "start"])
        #expect(
            commands.startVM(spec())
                == Container.startCommand(
                    spec: spec(),
                    executable: "/bin/container",
                ),
        )
        #expect(commands.stopVM(spec()) == ["/bin/container", "stop", "moat.ws"])
        #expect(commands.listRunningVMs == ["/bin/container", "list", "--quiet"])
        #expect(commands.gitPath == "/opt/bin/git")
    }

    @Test
    func startCommand() {
        let command = Container.startCommand(
            spec: spec(),
            executable: "container",
        )
        #expect(command == [
            "container",
            "run",
            "-it",
            "--rm",
            "--name",
            "moat.ws",
            "--cpus",
            "2",
            "--memory",
            "4G",
            "-u",
            "robot",
            "-w",
            "/ws",
            "-v",
            "/state:/home/robot/.claude:rw",
            "-v",
            "/ws/.git:/ws/.git:ro",
            "moat:latest",
            "claude",
            "--model",
            "opus",
        ])
    }

    @Test
    func startCommandWithEnvFile() {
        let envFile = URL(fileURLWithPath: "/tokens.env")
        let command = Container.startCommand(
            spec: spec(envFile: envFile),
            executable: "container",
        )
        #expect(command[12...15] == ["-w", "/ws", "--env-file", "/tokens.env"])
    }
}
