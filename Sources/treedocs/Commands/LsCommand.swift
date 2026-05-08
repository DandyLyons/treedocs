import ArgumentParser

struct LsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ls",
        abstract: "Render the documented repository tree."
    )

    @OptionGroup var options: RepositoryOptions
    @Argument(help: "An optional subtree path to render.")
    var targetPath: String?

    mutating func run() throws {
        print(try TreedocsService().renderTree(at: options.path, subtreePath: targetPath))
    }
}
