/// The commands that run sessions' VMs, as provided by the tool that runs VMs
/// (e.g., `Container`). Each is looked up on `PATH`.
public struct SessionCommands: Sendable {
    /// Succeeds if the tool's background system, which runs VMs, is running.
    public var checkSystem: [String]
    /// Starts the tool's background system. May prompt on the session's
    /// terminal (e.g., to install a component).
    public var startSystem: [String]
    /// Returns the command that runs a VM on the terminal it's started with,
    /// until the VM exits.
    public var start: @Sendable (VMLaunchSpec) -> [String]
    /// Returns the command that stops a VM, causing `start` to exit.
    public var stop: @Sendable (VMLaunchSpec) -> [String]

    public init(
        checkSystem: [String],
        startSystem: [String],
        start: @escaping @Sendable (VMLaunchSpec) -> [String],
        stop: @escaping @Sendable (VMLaunchSpec) -> [String],
    ) {
        self.checkSystem = checkSystem
        self.startSystem = startSystem
        self.start = start
        self.stop = stop
    }
}
