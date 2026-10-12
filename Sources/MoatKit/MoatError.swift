import Foundation

public enum MoatError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case notADirectory(String)
    case notAFile(String)
    case duplicateSkill(String)
    case invalidSettingsFile(String)
    case commandFailed([String], status: Int32)

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
        case .commandFailed(let argv, let status):
            "`\(argv.joined(separator: " "))` failed with exit status \(status)"
        }
    }

    public var errorDescription: String? { description }
}
