import ArgumentParser

/// Implements the `treedocs createREADME` command.
struct CreateReadmeCommand: ParsableCommand {
    /// Command metadata for materializing directory documentation as README stubs.
    static let configuration = CommandConfiguration(
        commandName: "createREADME",
        abstract: "Create README.md stubs from directory documentation in treedocs.yaml.",
        discussion: "Existing exact README.md files are skipped. Recursive creation respects ignore rules and stops beneath nested treedocs.yaml boundaries."
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// Directory in which to create README.md, relative to the selected repository root.
    @Argument(help: "The target directory, relative to the selected repository root.")
    var directory: String

    /// Whether to create stubs in the target and all eligible descendant directories.
    @Flag(name: .shortAndLong, help: "Create README.md stubs recursively.")
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
            lines.append("Created README files:")
            lines.append(contentsOf: result.createdPaths.map { "- \($0)" })
        }

        if !result.skippedPaths.isEmpty {
            lines.append("Skipped existing README files:")
            lines.append(contentsOf: result.skippedPaths.map { "- \($0)" })
        }

        lines.append("Created \(result.createdPaths.count), skipped \(result.skippedPaths.count).")
        if !result.createdPaths.isEmpty {
            lines.append("Next step: run `treedocs sync`.")
        }
        return lines
    }
}
