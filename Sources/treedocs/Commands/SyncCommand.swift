import ArgumentParser
import Darwin

/// Implements the `treedocs sync` command.
struct SyncCommand: ParsableCommand {
    /// Command metadata for reconciling state with the filesystem.
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Reconcile the YAML tree with the current filesystem layout.",
        discussion: "Nested treedocs.yaml files mark delegated documentation roots. Sync keeps the child folder in the parent tree but does not merge descendants owned by the nested state file."
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// Reconciles the stored tree with the current filesystem and prints the resulting signature.
    mutating func run() throws {
        let interactive = Self.shouldRunInteractively(
            nonInteractive: options.nonInteractive,
            stdinIsTTY: isatty(STDIN_FILENO) == 1,
            stdoutIsTTY: isatty(STDOUT_FILENO) == 1
        )

        let result = try TreedocsService().syncResult(
            at: options.path,
            interactive: interactive,
            missingDescriptionCollector: interactive ? NooraMissingDescriptionCollector() : nil
        )
        if result.saved {
            print("Synced treedocs.yaml (\(result.file.signature ?? "no signature"))")
            Self.printRemainingIssues(missingDescriptions: result.missingDescriptions)
        } else {
            print("Sync cancelled; no changes saved.")
        }
    }

    static func shouldRunInteractively(nonInteractive: Bool, stdinIsTTY: Bool, stdoutIsTTY: Bool) -> Bool {
        !nonInteractive && stdinIsTTY && stdoutIsTTY
    }

    static func remainingIssueMessages(missingDescriptions: [String]) -> [String] {
        guard !missingDescriptions.isEmpty else { return [] }

        return ["Missing descriptions:"]
            + missingDescriptions.sorted().map { "- \($0)" }
            + ["Next steps:", "- \(CheckCommand.missingDescriptionNextStep)"]
    }

    private static func printRemainingIssues(missingDescriptions: [String]) {
        for message in remainingIssueMessages(missingDescriptions: missingDescriptions) {
            print(message)
        }
    }
}
