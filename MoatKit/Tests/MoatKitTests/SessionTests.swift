import Foundation
import Testing
@testable import MoatKit

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SessionTests {
    let spec = VMLaunchSpec(
        name: "moat.SessionTests",
        image: "",
        cpus: 1,
        memory: "",
        user: "",
        workingDirectory: "/",
        envFile: nil,
        mounts: [],
        command: [],
    )

    func start(
        _ script: String,
        stopCommand: [String] = ["false"],
        size: TerminalSize,
    ) throws -> Session {
        try Session.start(
            spec: spec,
            commands: SessionCommands(
                start: ["sh", "-c", script],
                stop: stopCommand,
            ),
            size: size,
        )
    }

    /// Reads `session`'s output until it contains `text`.
    func waitForOutput(_ text: String, session: Session) async throws {
        var output: [UInt8] = []
        for try await chunk in session.outputStream {
            output += chunk
            if String(decoding: output, as: UTF8.self).contains(text) {
                return
            }
        }
    }

    @Test
    func runsOnATerminal() async throws {
        let session = try start(
            #"stty size; read line; echo "got $line"; exit 3"#,
            size: TerminalSize(columns: 100, rows: 30),
        )
        session.write(ArraySlice("hi\r".utf8))

        var outputBytes: [UInt8] = []
        for try await chunk in session.outputStream {
            outputBytes += chunk
        }
        await session.waitForExit()
        let output = String(decoding: outputBytes, as: UTF8.self)
        #expect(output.contains("30 100"))
        #expect(output.contains("got hi"))
        #expect(session.state == .exited(code: 3))
    }

    @Test
    func resize() async throws {
        let session = try start(
            "trap 'stty size; exit 0' WINCH; echo ready; while :; do sleep 0.05; done",
            size: TerminalSize(columns: 80, rows: 24),
        )

        var outputBytes: [UInt8] = []
        var iterator = session.outputStream.makeAsyncIterator()
        while
            !String(decoding: outputBytes, as: UTF8.self).contains("ready"),
            let chunk = try await iterator.next()
        {
            outputBytes += chunk
        }
        session.resize(TerminalSize(columns: 90, rows: 20))
        while let chunk = try await iterator.next() {
            outputBytes += chunk
        }
        await session.waitForExit()
        let output = String(decoding: outputBytes, as: UTF8.self)
        #expect(output.contains("20 90"))
        #expect(session.state == .exited(code: 0))
    }

    @Test
    func stopRunsStopCommand() async throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appending(path: "moat-SessionTests-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: pidFile)
        }
        let session = try start(
            "echo $$ > '\(pidFile.path)'; echo ready; exec sleep 100",
            stopCommand: ["sh", "-c", "kill -TERM $(cat '\(pidFile.path)')"],
            size: TerminalSize(columns: 80, rows: 24),
        )
        try await waitForOutput("ready", session: session)

        try await session.stop()
        #expect(session.state == .signaled(signal: SIGTERM))
    }

    @Test
    func stopFailureKeepsRunning() async throws {
        let session = try start(
            "echo ready; read line; exit 0",
            size: TerminalSize(columns: 80, rows: 24),
        )
        try await waitForOutput("ready", session: session)

        await #expect(throws: MoatError.self) {
            try await session.stop()
        }
        #expect(session.state == .running)

        session.write(ArraySlice("\r".utf8))
        await session.waitForExit()
        #expect(session.state == .exited(code: 0))
    }

    @Test
    func launchFailure() async throws {
        let session = try Session.start(
            spec: spec,
            commands: SessionCommands(
                start: ["moat-no-such-command"],
                stop: ["false"],
            ),
            size: TerminalSize(columns: 80, rows: 24),
        )
        for try await _ in session.outputStream {}
        await session.waitForExit()
        switch session.state {
        case .failed:
            break
        case .running, .stopping, .exited, .signaled:
            Issue.record("Unexpected state: \(session.state)")
        }
    }
}
