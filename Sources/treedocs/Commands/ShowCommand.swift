import ArgumentParser

struct ShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Render a documented path with inline descriptions.",
        discussion: "Displays the documented tree rooted at the given path."
    )

    @OptionGroup var options: RepositoryOptions
    @Argument(help: "The documented path to render.")
    var targetPath: String
    @Flag(name: .long, help: "Skip validation before rendering.")
    var noCheck = false

    mutating func run() throws {
        try Self.render(options: options, targetPath: targetPath, noCheck: noCheck)
    }

    static func render(options: RepositoryOptions, targetPath: String, noCheck: Bool) throws {
        let output = try TreedocsService().show(at: options.path, path: targetPath, checkFirst: !noCheck)
        print(output)
    }
}
