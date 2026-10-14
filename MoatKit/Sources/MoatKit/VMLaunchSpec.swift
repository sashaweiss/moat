import Foundation

/// A directory or file on the host mounted into an agent VM.
public struct Mount: Sendable {
    public enum Access: Sendable {
        case readOnly
        case readWrite
    }

    public var source: URL
    public var destination: String
    public var access: Access
}

/// All the details needed to launch a VM and run a command.
public struct VMLaunchSpec: Sendable {
    public var name: String
    public var image: String
    public var cpus: Int
    public var memory: String
    public var user: String
    public var workingDirectory: String
    public var envFile: URL?
    /// Mounts, in order. Mounts nested inside other mounts come after their
    /// parent.
    public var mounts: [Mount]
    /// The command to run in the VM.
    public var command: [String]
}
