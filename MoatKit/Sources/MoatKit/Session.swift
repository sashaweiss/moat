import CMoatKit
import Foundation
import Observation
import Subprocess
import Synchronization
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

    /// The size of `terminal`.
    public init(terminal: FileDescriptor) throws {
        var windowSize = winsize()
        guard ioctl(terminal.rawValue, kTIOCGWINSZ, &windowSize) == 0 else {
            throw Errno(rawValue: errno)
        }
        columns = Int(windowSize.ws_col)
        rows = Int(windowSize.ws_row)
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
    public private(set) var state: State = .running

    /// When the VM exited, once it has.
    public private(set) var exitDate: Date?

    /// Bytes the VM writes to the terminal. Finishes once the VM exits and its output is drained.
    /// Supports a single consumer.
    public nonisolated let outputStream: AsyncThrowingStream<ArraySlice<UInt8>, Error>
    private nonisolated let outputContinuation: AsyncThrowingStream<ArraySlice<UInt8>, Error>.Continuation

    /// Consumed by the task running the VM process, which can only be signaled from there.
    private nonisolated let vmSignalStream: AsyncStream<VMSignal>
    private nonisolated let vmSignalContinuation: AsyncStream<VMSignal>.Continuation

    /// A file descriptor for our end of the pseudo-terminal.
    private nonisolated let terminal: FileDescriptor

    /// When the VM last wrote to the terminal, if it has. Set by the thread
    /// reading the terminal.
    private nonisolated let lastOutputDateMutex = Mutex<Date?>(nil)

    /// When the VM last wrote to the terminal, if it has.
    public nonisolated var lastOutputDate: Date? {
        lastOutputDateMutex.withLock { $0 }
    }

    /// Serializes writes to the terminal.
    private nonisolated let writeQueue = DispatchQueue(label: "moat.Session.write")

    /// Runs the VM process, and finishes once it exits.
    @ObservationIgnored
    private var vmTask: Task<Void, Never>?

    /// Runs `startCommand` on a new pseudo-terminal of `size`, after running
    /// `startSystemCommand` there if `checkSystemCommand` fails. Each command
    /// starts with its executable's path.
    static func start(
        spec: VMLaunchSpec,
        checkSystemCommand: [String],
        startSystemCommand: [String],
        startCommand: [String],
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
            terminal: FileDescriptor(rawValue: terminal),
        )

        // Start the VM session.
        session.start(
            checkSystemCommand: checkSystemCommand,
            startSystemCommand: startSystemCommand,
            startCommand: startCommand,
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
        terminal: FileDescriptor,
    ) {
        self.spec = spec
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

    /// Stops the VM by running `command`, and waits for it to exit.
    /// - Note: if stopping fails, `state` remains `.running`.
    func stop(command: [String]) async throws {
        switch state {
        case .running:
            state = .stopping
        case .stopping, .exited, .signaled, .failed:
            await waitForExit()
            return
        }

        do {
            let result = try await Subprocess.run(
                .moatCommand(command),
                output: .discarded,
            )

            guard result.terminationStatus.isSuccess else {
                throw MoatError.commandFailed(
                    command,
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

    /// Starts `vmTask`, which runs the VM via `runVM(...)` and sets `state`
    /// and `exitDate` once it exits.
    private func start(
        checkSystemCommand: [String],
        startSystemCommand: [String],
        startCommand: [String],
        child: FileDescriptor,
    ) {
        precondition(vmTask == nil)

        vmTask = Task {
            state = await runVM(
                checkSystemCommand: checkSystemCommand,
                startSystemCommand: startSystemCommand,
                startCommand: startCommand,
                child: child,
            )
            exitDate = Date()
        }
    }

    /// Runs `startSystemCommand` if `checkSystemCommand` fails, then runs
    /// `startCommand` with `child` as its stdio until it exits, handling
    /// `vmSignalStream` for it. Closes `child`.
    @concurrent
    private func runVM(
        checkSystemCommand: [String],
        startSystemCommand: [String],
        startCommand: [String],
        child stdio: FileDescriptor,
    ) async -> State {
        do {
            try await Self.startSystemIfNeeded(
                checkSystemCommand: checkSystemCommand,
                startSystemCommand: startSystemCommand,
                stdio: stdio,
            )
        } catch {
            // The VM won't start, so close our copy of its terminal here;
            // otherwise the pseudo-terminal stays open, and `outputStream`
            // never finishes.
            try? stdio.close()
            return .failed(description: String(describing: error))
        }

        var platformOptions = PlatformOptions()
        // Give the VM process its own session, so it doesn't share our
        // controlling terminal if we have one.
        platformOptions.createSession = true
        do {
            let result = try await Subprocess.run(
                .moatCommand(
                    startCommand,
                    platformOptions: platformOptions,
                ),
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

    /// Runs `startSystemCommand` if `checkSystemCommand` fails. Starting the
    /// system may prompt (e.g., to install a component), so it runs with
    /// `stdio`, the session's terminal.
    @concurrent
    private static func startSystemIfNeeded(
        checkSystemCommand: [String],
        startSystemCommand: [String],
        stdio: FileDescriptor,
    ) async throws {
        let check = try await Subprocess.run(
            .moatCommand(checkSystemCommand),
            output: .discarded,
        )
        if check.terminationStatus.isSuccess {
            return
        }

        let start = try await Subprocess.run(
            .moatCommand(startSystemCommand),
            input: .fileDescriptor(stdio, closeAfterSpawningProcess: false),
            output: .fileDescriptor(stdio, closeAfterSpawningProcess: false),
            error: .fileDescriptor(stdio, closeAfterSpawningProcess: false),
        )
        if !start.terminationStatus.isSuccess {
            throw MoatError.commandFailed(
                startSystemCommand,
                status: start.terminationStatus,
            )
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
                lastOutputDateMutex.withLock { $0 = Date() }
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
