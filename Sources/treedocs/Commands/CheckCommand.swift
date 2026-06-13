import ArgumentParser

/// Implements the `treedocs check` command.
struct CheckCommand: ParsableCommand {
    /// Command metadata for non-mutating drift checks.
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Validate the stored tree against the filesystem and report drift.",
        discussion: "Filesystem validation stops at nested treedocs.yaml boundaries. A parent tree should document the delegated child folder, not the files and directories beneath it."
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// Reports stale signatures and missing descriptions for the selected repository.
    mutating func run() throws {
        let report = try TreedocsService().check(at: options.path)

        printSection("Schema validation failures", values: report.schemaErrors)

        if report.hasSignatureDrift {
            print("Stale tree: stored signature \(report.storedSignature ?? "<missing>") does not match current signature \(report.currentSignature)")
        }

        printSection("Missing paths", values: report.missingPaths)
        printSection("Extra documented paths", values: report.extraPaths)
        printSection("Changed paths", values: report.changedPaths)
        printSection("Nested documentation boundaries", values: report.nestedBoundaries)
        printSection("Shadowed child-owned paths", values: report.shadowedPaths)
        printSection("Missing descriptions", values: report.missingDescriptions)

        if !report.hasIssues {
            print("Tree is up to date.")
            return
        }

        printSection("Next steps", values: Self.nextSteps(for: report))

        if report.shouldFail {
            throw ExitCode(1)
        }
    }

    static func nextSteps(for report: CheckReport) -> [String] {
        guard report.shouldFail else { return [] }

        var steps: [String] = []
        if !report.schemaErrors.isEmpty || report.hasSignatureDrift || !report.missingPaths.isEmpty || !report.extraPaths.isEmpty || !report.changedPaths.isEmpty || !report.shadowedPaths.isEmpty {
            steps.append("Run `treedocs sync` to reconcile filesystem changes, refresh the stored signature, and repair generated schema state.")
        }
        if !report.shadowedPaths.isEmpty {
            steps.append("Nested `treedocs.yaml` files own their descendants; `treedocs sync` keeps only delegated boundary folders in the parent tree.")
        }
        if !report.missingDescriptions.isEmpty {
            steps.append("Add missing descriptions with `treedocs update <path> --description \"...\"`, or edit `treedocs.yaml` directly.")
        }

        return steps
    }

    private func printSection(_ title: String, values: [String]) {
        guard !values.isEmpty else { return }
        print("\(title):")
        for value in values.sorted() {
            print("- \(value)")
        }
    }
}
