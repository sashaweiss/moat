import Foundation
import PackagePlugin

/// Generates `Version.swift`, declaring `moatVersion` as the
/// `MARKETING_VERSION` in the repository's `Version.xcconfig`, which is also
/// the Xcode project's version.
@main
struct VersionPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target,
    ) throws -> [Command] {
        let xcconfigFile = context.package.directoryURL
            .deletingLastPathComponent()
            .appending(path: "Version.xcconfig")
        let outputFile = context.pluginWorkDirectoryURL
            .appending(path: "Version.swift")
        return [
            .buildCommand(
                displayName: "Generate moat's version",
                executable: try context.tool(named: "VersionGenerator").url,
                arguments: [xcconfigFile.path, outputFile.path],
                inputFiles: [xcconfigFile],
                outputFiles: [outputFile],
            ),
        ]
    }
}
