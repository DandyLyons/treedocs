import ArgumentParser

/// Provides command-line options shared by commands that operate on a repository.
struct RepositoryOptions: ParsableArguments {
    /// Repository root used for state, config, ignore, and filesystem operations.
    @Option(name: .shortAndLong, help: "The path to the repository root.")
    var path: String = "."

    /// Disables terminal UI even when the process is attached to a TTY.
    @Flag(name: [.customShort("n"), .long], help: "Disable interactive terminal UI.")
    var nonInteractive = false
}
