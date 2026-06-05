import ArgumentParser

/// Implements the `treedocs init` command.
struct InitCommand: ParsableCommand {
    /// Command metadata for creating initial treedocs state.
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scan the repository and create an initial treedocs.yaml."
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// Whether an existing `treedocs.yaml` may be replaced.
    @Flag(help: "Overwrite an existing treedocs.yaml.")
    var force = false

    /// Creates the initial state file for the selected repository.
    mutating func run() throws {
        let repositoryPaths = try RepositoryPaths(rootPath: options.path)
        _ = try TreedocsService().initialize(at: options.path, force: force)
        print("Initialized \(repositoryPaths.stateFile.string)")
    }
}
