import ArgumentParser
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
import Rainbow

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
            if result.signatureUnchanged {
                print(Self.noChangeMessage())
            } else {
                for message in Self.changeSummaryMessages(for: result.changes) {
                    print(message)
                }
            }
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

        return ["Missing descriptions:".blue]
            + missingDescriptions.sorted().map { "- \($0)" }
            + ["Next steps:".blue, "- \(CheckCommand.missingDescriptionNextStep)"]
    }

    static func noChangeMessage() -> String {
        "No change found.".green
    }

    static func changeSummaryMessages(for changes: SyncChanges, pathLimit: Int = 5) -> [String] {
        var messages = ["Changes found:".blue]
        messages.append(contentsOf: summaryLines(marker: "+".green, title: "Added", paths: changes.addedPaths, pathLimit: pathLimit))
        messages.append(contentsOf: summaryLines(marker: "-".red, title: "Removed", paths: changes.removedPaths, pathLimit: pathLimit))
        messages.append(contentsOf: summaryLines(marker: "-", title: "Changed type", paths: changes.changedTypePaths, pathLimit: pathLimit))
        return messages.count == 1 ? [] : messages
    }

    private static func summaryLines(marker: String, title: String, paths: [String], pathLimit: Int) -> [String] {
        guard !paths.isEmpty else { return [] }

        let shownPaths = paths.prefix(pathLimit).joined(separator: ", ")
        let remainingCount = paths.count - min(paths.count, pathLimit)
        let suffix = remainingCount > 0 ? ", +\(remainingCount) more" : ""
        return ["\(marker) \(title): \(paths.count) (\(shownPaths)\(suffix))"]
    }

    private static func printRemainingIssues(missingDescriptions: [String]) {
        for message in remainingIssueMessages(missingDescriptions: missingDescriptions) {
            print(message)
        }
    }
}
