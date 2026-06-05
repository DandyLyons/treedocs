import ArgumentParser

/// Implements the `treedocs sync` command.
struct SyncCommand: ParsableCommand {
    /// Command metadata for reconciling state with the filesystem.
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Reconcile the YAML tree with the current filesystem layout."
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// Whether missing descriptions should be collected from standard input while syncing.
    @Flag(help: "Prompt for descriptions on newly added entries.")
    var interactive = false

    /// Reconciles the stored tree with the current filesystem and prints the resulting signature.
    mutating func run() throws {
        let file = try TreedocsService().sync(at: options.path, interactive: interactive)
        print("Synced treedocs.yaml (\(file.signature ?? "no signature"))")
    }
}
