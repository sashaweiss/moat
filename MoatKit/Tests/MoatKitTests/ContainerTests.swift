import Foundation
import Testing
@testable import MoatKit

struct ContainerTests {
    func spec(envFile: URL? = nil) -> VMLaunchSpec {
        VMLaunchSpec(
            name: "moat.ws",
            image: "moat:base",
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
        #expect(
            commands.listRunningVMs.command
                == ["/bin/container", "list", "--quiet"],
        )
        #expect(
            commands.listImages.command
                == ["/bin/container", "image", "list", "--format", "json"],
        )
        #expect(commands.gitPath == "/opt/bin/git")
    }

    @Test
    func runningVMNames() {
        let output = Data(" moat.a\n\nmoat.b \n".utf8)
        #expect(
            Container.runningVMNames(output: output) == ["moat.a", "moat.b"],
        )
    }

    @Test
    func imageNames() throws {
        // Abridged from `container image list --format json`.
        let output = Data(#"""
        [
            {
                "configuration": {
                    "creationDate": "2026-10-05T00:00:00Z",
                    "descriptor": {
                        "digest": "sha256:7c7b2c96",
                        "mediaType": "application/vnd.oci.image.index.v1+json",
                        "size": 5651
                    },
                    "name": "docker.io/library/debian:bookworm-slim"
                },
                "id": "7c7b2c96",
                "variants": [{"digest": "sha256:a1b86db5", "size": 28138688}]
            },
            {
                "configuration": {
                    "descriptor": {
                        "annotations": {
                            "com.apple.containerization.image.name": "moat:base"
                        }
                    },
                    "name": "moat:base"
                },
                "id": "9332d539",
                "variants": []
            }
        ]
        """#.utf8)
        #expect(
            try Container.imageNames(output: output)
                == ["docker.io/library/debian:bookworm-slim", "moat:base"],
        )
    }

    @Test
    func imageNamesFailsOnUnexpectedOutput() {
        let output = Data(#"[{"name": "moat:base"}]"#.utf8)
        #expect(throws: DecodingError.self) {
            try Container.imageNames(output: output)
        }
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
            "moat:base",
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
