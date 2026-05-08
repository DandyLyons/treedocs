import ArgumentParser

struct PathCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "path",
        abstract: "Return the first documented path matching a query."
    )

    @OptionGroup var options: RepositoryOptions
    @Argument(help: "A case-insensitive path query.")
    var query: String

    mutating func run() throws {
        if let match = try TreedocsService().findPath(at: options.path, query: query) {
            print(match)
            return
        }
        throw ExitCode(1)
    }
}
