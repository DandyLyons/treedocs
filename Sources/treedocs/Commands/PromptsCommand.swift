import ArgumentParser

struct PromptsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prompts",
        abstract: "Generate prompts for maintaining treedocs.yaml.",
        subcommands: [PromptsFillCommand.self]
    )
}

struct PromptsFillCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fill",
        abstract: "Print a prompt for filling missing descriptions."
    )

    @OptionGroup var options: RepositoryOptions

    mutating func run() throws {
        print(try TreedocsService().fillPrompt(at: options.path))
    }
}
