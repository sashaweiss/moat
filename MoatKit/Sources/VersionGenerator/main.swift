import Foundation

// Usage: VersionGenerator <xcconfig file> <output file>
//
// Writes a Swift file declaring `moatVersion` as the `MARKETING_VERSION` set
// in the xcconfig file.

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: VersionGenerator <xcconfig file> <output file>")
    exit(1)
}
let xcconfigFile = URL(filePath: arguments[1])
let outputFile = URL(filePath: arguments[2])

let xcconfig = try String(contentsOf: xcconfigFile, encoding: .utf8)
var version: String?
for line in xcconfig.split(separator: "\n") {
    let parts = line.split(separator: "=", maxSplits: 1)
    guard
        parts.count == 2,
        parts[0].trimmingCharacters(in: .whitespaces) == "MARKETING_VERSION"
    else {
        continue
    }
    version = parts[1].trimmingCharacters(in: .whitespaces)
}
guard let version, !version.isEmpty else {
    print("error: no MARKETING_VERSION in \(xcconfigFile.path)")
    exit(1)
}

let source = """
    // Generated from \(xcconfigFile.lastPathComponent). Do not edit.

    /// moat's version, as `moat --version` prints it.
    let moatVersion = "\(version)"

    """
try source.write(to: outputFile, atomically: true, encoding: .utf8)
