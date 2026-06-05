import ArgumentParser

/// Groups commands that discover treedocs configuration and state files.
struct ConfigCommand: ParsableCommand {
    /// Command metadata for configuration discovery subcommands.
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Discover treedocs configuration and state files.",
        subcommands: [ConfigShowCommand.self]
    )
}

/// Implements the `treedocs config show` command.
struct ConfigShowCommand: ParsableCommand {
    /// Command metadata for recursively listing treedocs-related files.
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "List treedocs-related files under a path."
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// File or directory to search, relative to the selected repository root.
    @Argument(help: "The directory to search recursively.")
    var targetPath: String

    /// Lists treedocs-related files under the requested path.
    mutating func run() throws {
        let files = try TreedocsService().configFiles(at: options.path, under: targetPath)
        for file in files {
            print(file)
        }
    }
}
