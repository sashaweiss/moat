/// Commands Moat needs to run on the host.
public struct HostCommands: Sendable {
    /// Succeeds if the tool's background system, which runs VMs, is running.
    public var checkSystem: [String]
    /// Starts the tool's background system. May prompt on the session's
    /// terminal (e.g., to install a component).
    public var startSystem: [String]
    /// Returns the command that runs a VM on the terminal it's started with,
    /// until the VM exits.
    public var startVM: @Sendable (VMLaunchSpec) -> [String]
    /// Returns the command that stops a VM, causing `startVM` to exit.
    public var stopVM: @Sendable (VMLaunchSpec) -> [String]
    /// Prints the names of the running VMs, one per line.
    public var listRunningVMs: [String]
    /// Prints the images as a JSON array of objects, each with its name at
    /// `configuration.name`.
    public var listImages: [String]

    /// Path to a `git` executable.
    public var gitPath: String

    public init(
        checkSystem: [String],
        startSystem: [String],
        startVM: @escaping @Sendable (VMLaunchSpec) -> [String],
        stopVM: @escaping @Sendable (VMLaunchSpec) -> [String],
        listRunningVMs: [String],
        listImages: [String],
        gitPath: String,
    ) {
        self.checkSystem = checkSystem
        self.startSystem = startSystem
        self.startVM = startVM
        self.stopVM = stopVM
        self.listRunningVMs = listRunningVMs
        self.listImages = listImages
        self.gitPath = gitPath
    }
}
