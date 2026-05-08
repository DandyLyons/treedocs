import ArgumentParser

struct CheckCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Validate the stored tree against the filesystem and report drift."
    )

    @OptionGroup var options: RepositoryOptions

    mutating func run() throws {
        let report = try TreedocsService().check(at: options.path)

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
