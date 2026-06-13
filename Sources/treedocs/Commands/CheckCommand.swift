import ArgumentParser

/// Implements the `treedocs check` command.
struct CheckCommand: ParsableCommand {
    /// Command metadata for non-mutating drift checks.
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Validate the stored tree against the filesystem and report drift."
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// Reports stale signatures and missing descriptions for the selected repository.
    mutating func run() throws {
        let report = try TreedocsService().check(at: options.path)

        for error in report.schemaErrors {
            print(error)
        }

        if report.hasSignatureDrift {
            print("Stale tree: stored signature \(report.storedSignature ?? "<missing>") does not match current signature \(report.currentSignature)")
        }

        if !report.missingDescriptions.isEmpty {
            for path in report.missingDescriptions.sorted() {
                print("Missing description: \(path)")
            }
        }

        if !report.hasIssues {
            print("Tree is up to date.")
            return
        }

        if report.shouldFail {
            throw ExitCode(1)
        }
    }
}
