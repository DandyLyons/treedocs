import ArgumentParser

/// Implements the `treedocs explore` command.
struct ExploreCommand: ParsableCommand {
    /// Command metadata for progressively disclosing the documented tree.
    static let configuration = CommandConfiguration(
        commandName: "explore",
        abstract: "Render a shallow documented tree with selected directories expanded."
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// Documentation paths to expand one level within the root tree.
    @Argument(help: "Optional paths to expand one level. Defaults to the repository root.")
    var targetPaths: [String] = []

    /// Whether long descriptions should be rendered without truncation.
    @Flag(name: [.customShort("f"), .long], help: "Render full descriptions instead of truncating them.")
    var fullDescriptions = false

    /// Renders the root tree with requested paths expanded.
    mutating func run() throws {
        print(try TreedocsService().explore(at: options.path, expandedPaths: targetPaths, fullDescriptions: fullDescriptions))
    }
}
