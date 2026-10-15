import CMoatKit
import Foundation
import Observation
import Subprocess
#if canImport(Darwin)
import Darwin
import System
#else
import Glibc
import SystemPackage
#endif

/// The size of a terminal, in characters.
public struct TerminalSize: Equatable, Sendable {
    public var columns: Int
    public var rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

/// A running agent VM, attached to a pseudo-terminal.
///
/// - Note: The VM process runs in its own session, without a controlling
/// terminal. It consequently won't get SIGWINCH on resize, so callers should
/// call `resize()` on a `Session` as appropriate.
///
/// - Note: The session ends once nothing holds the VM's end of the pseudo-terminal
/// open. If the VM process exits, and someone keeps the pseudo-terminal open,
/// the session will be `.running` forever.
@MainActor
@Observable
public final class Session {
    public enum State: Equatable, Sendable {
        case running
        case stopping
        /// The VM process exited with `code`.
        case exited(code: Int32)
        /// The VM process was killed by `signal`.
        case signaled(signal: Int32)
        /// The VM process couldn't be launched (or, unexpectedly, waited on).
        case failed(description: String)
    }

    /// Signals the session can send to its running VM process.
    private enum VMSignal: Sendable {
        case windowSizeChange
    }

    public let spec: VMLaunchSpec
    /// Manipulate the VM.
    private let commands: SessionCommands
    public private(set) var state: State = .running

    /// Bytes the VM writes to the terminal. Finishes once the VM exits and its output is drained.
    /// Supports a single consumer.
    public nonisolated let outputStream: AsyncThrowingStream<ArraySlice<UInt8>, Error>
    private nonisolated let outputContinuation: AsyncThrowingStream<ArraySlice<UInt8>, Error>.Continuation

    /// Consumed by the task running the VM process, which can only be signaled from there.
    private nonisolated let vmSignalStream: AsyncStream<VMSignal>
    private nonisolated let vmSignalContinuation: AsyncStream<VMSignal>.Continuation

    /// A file descriptor for our end of the pseudo-terminal.
    private nonisolated let terminal: FileDescriptor

    /// Serializes writes to the terminal.
    private nonisolated let writeQueue = DispatchQueue(label: "moat.Session.write")

    /// Runs the VM process, and finishes once it exits.
    @ObservationIgnored
    private var vmTask: Task<Void, Never>?

    /// Runs `commands.start` on a new pseudo-terminal of `size`. `stop()` runs
    /// `commands.stop`.
    public static func start(
        spec: VMLaunchSpec,
        commands: SessionCommands,
        size: TerminalSize,
    ) throws -> Session {
        var windowSize = windowSize(for: size)
        var terminal: Int32 = -1
        var child: Int32 = -1
        guard openpty(&terminal, &child, nil, nil, &windowSize) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        // Ensure that processes we spawn don't inherit these, since they're
        // tied to the lifetime of the pseudo-terminal and thereby the VM process.
        //
        // `Subprocess` should manage these safely, so this is defensive against
        // callers who don't.
        _ = fcntl(terminal, F_SETFD, FD_CLOEXEC)
        _ = fcntl(child, F_SETFD, FD_CLOEXEC)

        let session = Session(
            spec: spec,
            commands: commands,
            terminal: FileDescriptor(rawValue: terminal),
        )

        // Start the VM session.
        session.start(
            command: commands.start,
            child: FileDescriptor(rawValue: child),
        )

        // Reading blocks if the VM isn't writing, so it gets it own thread.
        Thread.detachNewThread {
            session.readOutput()
        }

        return session
    }

    private init(
        spec: VMLaunchSpec,
        commands: SessionCommands,
        terminal: FileDescriptor,
    ) {
        self.spec = spec
        self.commands = commands
        self.terminal = terminal
        (outputStream, outputContinuation) = AsyncThrowingStream.makeStream(of: ArraySlice<UInt8>.self)
        (vmSignalStream, vmSignalContinuation) = AsyncStream.makeStream(of: VMSignal.self)
    }

    deinit {
        try? terminal.close()
    }

    /// Sends `bytes` (e.g., keyboard input) to the VM. Can be called from any
    /// thread; writes happen in the order they're called.
    public nonisolated func write(_ bytes: ArraySlice<UInt8>) {
        // Writing blocks, so it gets its own queue.
        writeQueue.async {
            _ = try? self.terminal.writeAll(bytes)
        }
    }

    /// Resizes the terminal, and notifies the VM.
    public func resize(_ size: TerminalSize) {
        var windowSize = windowSize(for: size)
        _ = ioctl(terminal.rawValue, kTIOCSWINSZ, &windowSize)
        vmSignalContinuation.yield(.windowSizeChange)
    }

    /// Stops the VM and waits for it to exit.
    /// - Note: if stopping fails, `state` remains `.running`.
    public func stop() async throws {
        switch state {
        case .running:
            state = .stopping
        case .stopping, .exited, .signaled, .failed:
            await waitForExit()
            return
        }

        do {
            let result = try await Subprocess.run(
                .name(commands.stop[0]),
                arguments: Arguments(Array(commands.stop.dropFirst())),
                output: .discarded,
            )

            guard result.terminationStatus.isSuccess else {
                throw MoatError.commandFailed(
                    commands.stop,
                    status: result.terminationStatus,
                )
            }

            await waitForExit()
        } catch {
            switch state {
            case .stopping:
                state = .running
            case .running, .exited, .signaled, .failed:
                break
            }

            throw error
        }
    }

    /// Waits for the VM to exit.
    public func waitForExit() async {
        await vmTask?.value
    }

    // MARK: -

    /// Starts `vmTask`, which runs `command` via `runVM(startCommand:child:)`
    /// and sets `state` once it exits.
    private func start(
        command: [String],
        child: FileDescriptor,
    ) {
        precondition(vmTask == nil)

        vmTask = Task {
            state = await runVM(
                startCommand: command,
                child: child,
            )
        }
    }

    /// Runs `startCommand` with `child` as its stdio until it exits, handling
    /// `vmSignalStream` for it. Closes `child` once it's copied by the started
    /// command.
    @concurrent
    private func runVM(
        startCommand: [String],
        child stdio: FileDescriptor,
    ) async -> State {
        var platformOptions = PlatformOptions()
        // Give the VM process its own session, so it doesn't share our
        // controlling terminal if we have one.
        platformOptions.createSession = true
        do {
            let result = try await Subprocess.run(
                .name(startCommand[0]),
                arguments: Arguments(Array(startCommand.dropFirst())),
                platformOptions: platformOptions,
                // We want our copy closed after the process is spawned and has
                // its own copy, since otherwise it'll keep the pseudo-terminal
                // open after the VM process exits.
                input: .fileDescriptor(stdio, closeAfterSpawningProcess: true),
                output: .fileDescriptor(stdio, closeAfterSpawningProcess: true),
                error: .fileDescriptor(stdio, closeAfterSpawningProcess: true),
            ) { execution in
                for await signal in vmSignalStream {
                    switch signal {
                    case .windowSizeChange:
                        try? execution.send(signal: .windowSizeChange)
                    }
                }
            }
            switch result.terminationStatus {
            case .exited(let code):
                return .exited(code: code)
            case .signaled(let signal):
                return .signaled(signal: signal)
            }
        } catch {
            return .failed(description: String(describing: error))
        }
    }

    // MARK: -

    /// Reads from the terminal into `outputStream` until it's closed by the VM.
    /// - Parameter bufferSize: upper bound on the number of bytes read per chunk.
    private nonisolated func readOutput(
        bufferSize: Int = 8 * 1024,
    ) {
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        do {
            while true {
                // Returns as soon as any bytes are available, and at most
                // `buffer.count` of them.
                let count = try buffer.withUnsafeMutableBytes { bytes in
                    try terminal.read(into: bytes)
                }
                guard count > 0 else {
                    break
                }
                outputContinuation.yield(buffer[..<count])
            }
            outputContinuation.finish()
        } catch Errno.ioError {
            // Reading fails with EIO once nothing holds the VM's end of the
            // pseudo-terminal open, i.e., once the VM process has exited.
            outputContinuation.finish()
        } catch {
            outputContinuation.finish(throwing: error)
        }

        // The VM process has exited (it's done with its stdio), so stop
        // handling requests for it.
        vmSignalContinuation.finish()
    }
}

// MARK: -

private func windowSize(for size: TerminalSize) -> winsize {
    return winsize(
        ws_row: UInt16(size.rows),
        ws_col: UInt16(size.columns),
        ws_xpixel: 0,
        ws_ypixel: 0,
    )
}
