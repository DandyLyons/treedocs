import ArgumentParser

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scan the repository and create an initial treedocs.yaml."
    )

    @OptionGroup var options: RepositoryOptions
    @Flag(help: "Overwrite an existing treedocs.yaml.")
    var force = false

    mutating func run() throws {
        let repositoryPaths = try RepositoryPaths(rootPath: options.path)
        _ = try TreedocsService().initialize(at: options.path, force: force)
        print("Initialized \(repositoryPaths.stateFile.string)")
    }
}
