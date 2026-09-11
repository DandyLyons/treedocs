import ArgumentParser

/// Implements `treedocs createDoc`, also available through the `createREADME` alias.
///
/// Uses the exact-folder source override or `README.md`, preserving existing files and state.
/// See <doc:GettingStarted> for creation examples.
struct CreateReadmeCommand: ParsableCommand {
    /// Command names and help for materializing directory metadata as selected source files.
    static let configuration = CommandConfiguration(
        commandName: "createDoc",
        abstract: "Create configured documentation sources from directory documentation in treedocs.yaml.",
        discussion: "Uses README.md unless the exact folder has a documentation_sources override. Existing sources are skipped. Recursive creation respects ignore rules and nested treedocs.yaml boundaries.",
        aliases: ["createREADME"]
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// Directory in which to create the selected documentation source.
    @Argument(help: "The target directory, relative to the selected repository root.")
    var directory: String

    /// Whether to create stubs in the target and all eligible descendant directories.
    @Flag(name: .shortAndLong, help: "Create documentation stubs recursively.")
    var recursive = false

    /// Creates the requested stubs and prints a deterministic summary.
    mutating func run() throws {
        let result = try TreedocsService().createReadmes(
            at: options.path,
            targetPath: directory,
            recursive: recursive
        )
        for line in Self.summaryLines(for: result) {
            print(line)
        }
    }

    /// Builds concise output for created files, skipped collisions, totals, and the next step.
    static func summaryLines(for result: CreateReadmeResult) -> [String] {
        var lines: [String] = []
        if result.createdPaths.isEmpty {
            lines.append("No files created.")
        } else {
            lines.append("Created documentation files:")
            lines.append(contentsOf: result.createdPaths.map { "- \($0)" })
        }

        if !result.skippedPaths.isEmpty {
            lines.append("Skipped existing documentation files:")
            lines.append(contentsOf: result.skippedPaths.map { "- \($0)" })
        }

        lines.append("Created \(result.createdPaths.count), skipped \(result.skippedPaths.count).")
        if !result.createdPaths.isEmpty {
            lines.append("Next step: run `treedocs sync`.")
        }
        return lines
    }
}
