import ArgumentParser
import Foundation

/// A problem that stops the release.
struct ReleaseError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

@main
struct ReleaseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "moat-release",
        abstract: "Builds, signs, notarizes, and publishes a release of moat.",
        discussion: """
            The version comes from Version.xcconfig. The release is tagged \
            v<version>, and published to GitHub as a draft. Builds and \
            artifacts go in release/.
            """,
    )

    @Option(help: ArgumentHelp(
        "the identity to sign with, e.g. \"Developer ID Application: …\"",
        valueName: "identity",
    ))
    var signingIdentity: String

    @Option(help: ArgumentHelp(
        "the notarytool keychain profile to notarize with",
        valueName: "profile",
    ))
    var notaryProfile: String

    @Option(help: ArgumentHelp(
        "the git remote to release to, if the repository has more than one",
        valueName: "remote",
    ))
    var remote: String?

    @Option(help: ArgumentHelp(
        "the architecture to release, which this Mac must build for",
        valueName: "architecture",
    ))
    var architecture = "arm64"

    @Flag(help: "do everything but tag and publish")
    var dryRun = false

    func run() async throws {
        let repository = URL(
            filePath: try await outputOf(command: [
                "git",
                "rev-parse",
                "--show-toplevel",
            ]),
        )
        let version = try readVersion(repository: repository)
        let tag = "v\(version)"
        let releaseDirectory = repository.appending(path: "release")
        print("Releasing moat \(version) for \(architecture)")

        log("Checking tools")
        try checkTools()

        log("Checking the repository")
        let remote = try await findRemote(repository: repository)
        try await checkRepository(
            repository: repository,
            remote: remote,
            tag: tag,
        )

        log("Testing")
        try await runShowingOutput(
            [
                "swift",
                "test",
                "--scratch-path",
                releaseDirectory.appending(path: "build/test").path,
            ],
            directory: repository.appending(path: "MoatKit"),
        )

        let artifacts = [
            try await makeArtifact(
                architecture: architecture,
                version: version,
                repository: repository,
                releaseDirectory: releaseDirectory,
            ),
        ]

        guard !dryRun else {
            let zips = artifacts.map(\.zip.path).joined(separator: ", ")
            print("Dry run: made \(zips); not publishing.")
            return
        }
        try await publish(
            artifacts: artifacts,
            version: version,
            tag: tag,
            repository: repository,
            remote: remote,
        )
        print("Created a draft release, \(tag); review and publish it on GitHub.")
    }

    /// A signed, notarized build of moat for one architecture, as published.
    struct Artifact {
        var zip: URL
        var checksum: URL
    }

    /// Builds, signs, and notarizes moat for `architecture`, in
    /// `releaseDirectory`.
    func makeArtifact(
        architecture: String,
        version: String,
        repository: URL,
        releaseDirectory: URL,
    ) async throws -> Artifact {
        log("Building for \(architecture)")
        let binary = try await build(
            repository: repository,
            buildDirectory: releaseDirectory.appending(
                path: "build/\(architecture)",
            ),
        )
        let builtVersion = try await outputOf(
            command: [binary.path, "--version"],
        )
        guard builtVersion == version else {
            throw ReleaseError(
                "The build says it's version \(builtVersion), not \(version).",
            )
        }
        try await checkArchitecture(binary: binary, architecture: architecture)

        let architectureDirectory = releaseDirectory.appending(
            path: architecture,
        )
        try? FileManager.default.removeItem(at: architectureDirectory)
        try FileManager.default.createDirectory(
            at: architectureDirectory,
            withIntermediateDirectories: true,
        )
        let signedBinary = architectureDirectory.appending(path: "moat")
        try FileManager.default.copyItem(at: binary, to: signedBinary)

        log("Signing for \(architecture)")
        try await sign(binary: signedBinary)

        log("Notarizing for \(architecture)")
        let zip = releaseDirectory.appending(
            path: "moat-\(version)-macos-\(architecture).zip",
        )
        try? FileManager.default.removeItem(at: zip)
        try await runShowingOutput([
            "ditto",
            "-c",
            "-k",
            // Leave out extended attributes, which ditto otherwise stores as
            // a ._moat file that unzip extracts. The signature is in the
            // binary itself.
            "--norsrc",
            signedBinary.path,
            zip.path,
        ])
        try await notarize(zip: zip)

        return Artifact(zip: zip, checksum: try await writeChecksum(zip: zip))
    }

    /// Tags the release `tag`, pushes the tag to `remote`, and creates a
    /// draft GitHub release of `artifacts`, with the `Containerfile` to build
    /// moat's image.
    func publish(
        artifacts: [Artifact],
        version: String,
        tag: String,
        repository: URL,
        remote: String,
    ) async throws {
        log("Tagging \(tag)")
        try await runShowingOutput(
            ["git", "tag", "-a", tag, "-m", "moat \(version)"],
            directory: repository,
        )
        try await runShowingOutput(
            ["git", "push", remote, tag],
            directory: repository,
        )

        log("Creating a draft GitHub release")
        let files = artifacts.flatMap { artifact in
            [artifact.zip.path, artifact.checksum.path]
        } + [repository.appending(path: "Containerfile").path]
        try await runShowingOutput(
            ["gh", "release", "create", tag]
                + files
                + [
                    "--draft",
                    "--title",
                    "\(tag)",
                    "--generate-notes",
                ],
            directory: repository,
        )
    }

    /// Returns the `MARKETING_VERSION` in the repository's `Version.xcconfig`.
    func readVersion(repository: URL) throws -> String {
        let xcconfigFile = repository.appending(path: "Version.xcconfig")
        let xcconfig = try String(contentsOf: xcconfigFile, encoding: .utf8)
        for line in xcconfig.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            if
                parts.count == 2,
                parts[0].trimmingCharacters(in: .whitespaces)
                    == "MARKETING_VERSION"
            {
                return parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        throw ReleaseError("No MARKETING_VERSION in \(xcconfigFile.path).")
    }

    /// Checks that the tools the release runs are on `PATH`.
    func checkTools() throws {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = path.split(separator: ":").map(String.init)
        let tools = [
            "git",
            "swift",
            "lipo",
            "codesign",
            "ditto",
            "xcrun",
            "shasum",
            "gh",
        ]
        for tool in tools {
            let isOnPath = directories.contains { directory in
                FileManager.default.isExecutableFile(
                    atPath: "\(directory)/\(tool)",
                )
            }
            guard isOnPath else {
                throw ReleaseError("Couldn't find \(tool) on PATH.")
            }
        }
    }

    /// Returns `remote`, if it was given and exists, or else the repository's
    /// only remote.
    func findRemote(repository: URL) async throws -> String {
        let remotes = try await outputOf(
            command: ["git", "remote"],
            directory: repository,
        )
        .split(separator: "\n")
        .map(String.init)

        if let remote {
            guard remotes.contains(remote) else {
                throw ReleaseError("There's no remote named \(remote).")
            }
            return remote
        }
        guard remotes.count == 1 else {
            throw ReleaseError(
                "The repository has \(remotes.count) remotes; pass --remote.",
            )
        }
        return remotes[0]
    }

    /// Checks that the repository is on a clean `main` matching `remote`'s,
    /// and that `tag` hasn't been used, by a tag or a GitHub release.
    func checkRepository(
        repository: URL,
        remote: String,
        tag: String,
    ) async throws {
        let git = { (arguments: [String]) in
            try await outputOf(command: ["git"] + arguments, directory: repository)
        }

        guard try await git(["rev-parse", "--abbrev-ref", "HEAD"]) == "main" else {
            throw ReleaseError("Releases must come from main.")
        }

        guard try await git(["status", "--porcelain"]).isEmpty else {
            throw ReleaseError("The working tree has uncommitted changes.")
        }

        _ = try await git(["fetch", remote, "main", "--tags"])
        let head = try await git(["rev-parse", "HEAD"])
        let remoteMain = try await git(["rev-parse", "\(remote)/main"])
        guard head == remoteMain else {
            throw ReleaseError("main doesn't match \(remote)/main.")
        }

        guard try await git(["tag", "--list", tag]).isEmpty else {
            throw ReleaseError("The tag \(tag) already exists.")
        }

        let releaseTags = try await outputOf(
            command: [
                "gh",
                "release",
                "list",
                "--limit",
                "1000",
                "--json",
                "tagName",
                "--jq",
                ".[].tagName",
            ],
            directory: repository,
        )
        guard !releaseTags.split(separator: "\n").contains(Substring(tag)) else {
            throw ReleaseError("A GitHub release for \(tag) already exists.")
        }
    }

    /// Builds moat for release in `buildDirectory`, and returns the binary.
    func build(repository: URL, buildDirectory: URL) async throws -> URL {
        let moatKit = repository.appending(path: "MoatKit")
        let build = [
            "swift",
            "build",
            "-c",
            "release",
            "--scratch-path",
            buildDirectory.path,
        ]
        try await runShowingOutput(build, directory: moatKit)
        let binPath = try await outputOf(
            command: build + ["--show-bin-path"],
            directory: moatKit,
        )
        return URL(filePath: binPath).appending(path: "moat")
    }

    /// Checks that `binary` is for `architecture`. Builds are for this Mac's
    /// architecture, so each architecture is released from a Mac with it.
    func checkArchitecture(binary: URL, architecture: String) async throws {
        let architectures = try await outputOf(
            command: ["lipo", "-archs", binary.path],
        )
        guard architectures == architecture else {
            throw ReleaseError(
                "moat was built for \(architectures), not \(architecture).",
            )
        }
    }

    /// Signs `binary` for notarization, and verifies it.
    func sign(binary: URL) async throws {
        try await runShowingOutput([
            "codesign",
            "--sign",
            signingIdentity,
            "--options",
            "runtime",
            "--timestamp",
            "--force",
            binary.path,
        ])
        try await runShowingOutput([
            "codesign",
            "--verify",
            "--strict",
            "--verbose=2",
            binary.path,
        ])
    }

    /// Submits `zip` for notarization, and waits for it to be accepted.
    func notarize(zip: URL) async throws {
        let submission = try await outputOf(command: [
            "xcrun",
            "notarytool",
            "submit",
            zip.path,
            "--keychain-profile",
            notaryProfile,
            "--wait",
            "--output-format",
            "json",
        ])
        struct Submission: Decodable {
            var id: String
            var status: String
        }
        let result = try JSONDecoder().decode(
            Submission.self,
            from: Data(submission.utf8),
        )
        guard result.status == "Accepted" else {
            try? await runShowingOutput([
                "xcrun",
                "notarytool",
                "log",
                result.id,
                "--keychain-profile",
                notaryProfile,
            ])
            throw ReleaseError("Notarization ended as \(result.status).")
        }
    }

    /// Writes a SHA-256 checksum file for `zip`, and returns it.
    func writeChecksum(zip: URL) async throws -> URL {
        let checksum = try await outputOf(
            command: ["shasum", "-a", "256", zip.lastPathComponent],
            directory: zip.deletingLastPathComponent(),
        )
        let checksumFile = zip.appendingPathExtension("sha256")
        try (checksum + "\n").write(
            to: checksumFile,
            atomically: true,
            encoding: .utf8,
        )
        return checksumFile
    }
}
