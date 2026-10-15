import Foundation
import os

/// Logging, backed by `os.Logger`.
enum Logger {
    private static let logger = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Moat",
        category: "omnibus",
    )

    static func info(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    static func warn(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.fault("\(message, privacy: .public)")
    }
}
