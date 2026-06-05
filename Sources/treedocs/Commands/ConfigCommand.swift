import ArgumentParser

struct ConfigCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Discover treedocs configuration and state files.",
        subcommands: [ConfigShowCommand.self]
    )
}

struct ConfigShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "List treedocs-related files under a path."
    )

    @OptionGroup var options: RepositoryOptions
    @Argument(help: "The directory to search recursively.")
    var targetPath: String

    mutating func run() throws {
        let files = try TreedocsService().configFiles(at: options.path, under: targetPath)
        for file in files {
            print(file)
        }
    }
}
