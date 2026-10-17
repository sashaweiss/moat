import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

extension Subprocess.Configuration {
    /// A configuration that runs `command`: the path of an executable, then
    /// its arguments.
    static func moatCommand(
        _ command: [String],
        platformOptions: PlatformOptions = PlatformOptions(),
    ) -> Self {
        Self(
            executable: .path(FilePath(command[0])),
            arguments: Arguments(Array(command.dropFirst())),
            platformOptions: platformOptions,
        )
    }
}
