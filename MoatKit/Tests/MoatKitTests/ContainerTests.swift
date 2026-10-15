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
    func sessionCommands() {
        let commands = Container.sessionCommands
        #expect(commands.checkSystem == ["container", "system", "status"])
        #expect(commands.startSystem == ["container", "system", "start"])
        #expect(commands.start(spec()) == Container.startCommand(spec: spec()))
        #expect(commands.stop(spec()) == ["container", "stop", "moat.ws"])
    }

    @Test
    func startCommand() {
        #expect(Container.startCommand(spec: spec()) == [
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
        let command = Container.startCommand(spec: spec(envFile: envFile))
        #expect(command[12...15] == ["-w", "/ws", "--env-file", "/tokens.env"])
    }
}
