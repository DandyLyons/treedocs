import ArgumentParser

struct SyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Reconcile the YAML tree with the current filesystem layout."
    )

    @OptionGroup var options: RepositoryOptions
    @Flag(help: "Prompt for descriptions on newly added entries.")
    var interactive = false

    mutating func run() throws {
        let file = try TreedocsService().sync(at: options.path, interactive: interactive)
        print("Synced treedocs.yaml (\(file.signature ?? "no signature"))")
    }
}
