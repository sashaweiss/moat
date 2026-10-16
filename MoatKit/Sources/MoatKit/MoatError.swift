import Foundation
import Subprocess

public enum MoatError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case notADirectory(String)
    case notAFile(String)
    case duplicateSkill(String)
    case invalidSettingsFile(String)
    case invalidMetadataFile(String)
    case sessionAlreadyRunning(Workspace)
    case sessionRunningElsewhere(Workspace)
    case sessionRunning(Workspace)
    case commandFailed([String], status: TerminationStatus)

    public var description: String {
        switch self {
        case .notADirectory(let path):
            "not a directory: \(path)"
        case .notAFile(let path):
            "not a file: \(path)"
        case .duplicateSkill(let name):
            "duplicate skill: \(name)"
        case .invalidSettingsFile(let path):
            "invalid settings file: \(path)"
        case .invalidMetadataFile(let path):
            "invalid session metadata file: \(path)"
        case .sessionRunning(let workspace):
            "the session for \(workspace) is running"
        case .sessionRunningElsewhere(let workspace):
            "a session for \(workspace) is already running elsewhere"
        case .sessionAlreadyRunning(let workspace):
            "a session is already running for \(workspace)"
        case .commandFailed(let argv, let status):
            "`\(argv.joined(separator: " "))` failed: \(status)"
        }
    }

    public var errorDescription: String? { description }
}
