import ArgumentParser

@main
struct TreeDocs: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "treedocs",
        abstract: "Generate and maintain a YAML-based architectural map of a repository.",
        subcommands: [
            InitCommand.self,
            SyncCommand.self,
            CheckCommand.self,
            InspectCommand.self,
            UpdateCommand.self,
            LsCommand.self,
            PathCommand.self,
        ]
    )
}
