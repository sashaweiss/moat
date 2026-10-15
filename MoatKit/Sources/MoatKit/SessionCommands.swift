/// The commands a `Session` runs to start and stop its VM, as provided by the
/// tool that runs VMs (e.g., `Container`). Each is looked up on `PATH`.
public struct SessionCommands: Equatable, Sendable {
    /// Runs the VM on the terminal it's started with, until the VM exits.
    public var start: [String]
    /// Stops the VM, causing `start` to exit.
    public var stop: [String]

    public init(start: [String], stop: [String]) {
        self.start = start
        self.stop = stop
    }
}
