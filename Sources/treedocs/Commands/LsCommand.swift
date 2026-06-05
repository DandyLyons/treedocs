import ArgumentParser

/// Implements the `treedocs ls` command.
struct LsCommand: ParsableCommand {
    /// Command metadata for listing the documented tree.
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "Render the documented repository tree."
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// Optional documented subtree to render instead of the repository root.
    @Argument(help: "An optional subtree path to render.")
    var targetPath: String?

    /// Renders the complete tree or a requested subtree.
    mutating func run() throws {
        print(try TreedocsService().renderTree(at: options.path, subtreePath: targetPath))
    }
}
