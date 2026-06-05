import ArgumentParser

/// Implements the `treedocs path` command.
struct PathCommand: ParsableCommand {
    /// Command metadata for shell-friendly path lookup.
    static let configuration = CommandConfiguration(
        commandName: "path",
        abstract: "Return the first documented path matching a query."
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// Case-insensitive text matched against documented paths and descriptions.
    @Argument(help: "A case-insensitive path query.")
    var query: String

    /// Prints the first documented path matching the query or exits with failure.
    mutating func run() throws {
        if let match = try TreedocsService().findPath(at: options.path, query: query) {
            print(match)
            return
        }
        throw ExitCode(1)
    }
}
