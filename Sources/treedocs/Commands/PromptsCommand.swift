import ArgumentParser

/// Groups commands that generate maintenance prompts for `treedocs.yaml`.
struct PromptsCommand: ParsableCommand {
    /// Command metadata for generated maintenance prompt subcommands.
    static let configuration = CommandConfiguration(
        commandName: "prompts",
        abstract: "Generate prompts for maintaining treedocs.yaml.",
        subcommands: [PromptsFillCommand.self]
    )
}

/// Implements the `treedocs prompts fill` command.
struct PromptsFillCommand: ParsableCommand {
    /// Command metadata for generating a missing-description prompt.
    static let configuration = CommandConfiguration(
        commandName: "fill",
        abstract: "Print a prompt for filling missing descriptions."
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// Prints a prompt for filling missing tree descriptions.
    mutating func run() throws {
        print(try TreedocsService().fillPrompt(at: options.path))
    }
}
