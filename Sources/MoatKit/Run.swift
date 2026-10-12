import Foundation

/// Runs `arguments` to completion, looking up `arguments[0]` on `PATH`, and
/// returns its exit status. Output goes to /dev/null by default; pass `nil`
/// to inherit this process's instead.
///
/// This waits for the process to exit before returning, so output sent to a
/// `Pipe` must fit in the pipe's buffer.
@discardableResult
func run(
    _ arguments: [String],
    in directory: URL? = nil,
    standardOutput: Any? = FileHandle.nullDevice,
    standardError: Any? = FileHandle.nullDevice,
) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    if let standardOutput {
        process.standardOutput = standardOutput
    }
    if let standardError {
        process.standardError = standardError
    }
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}
