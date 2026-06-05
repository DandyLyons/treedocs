import ArgumentParser

/// Provides command-line options shared by commands that operate on a repository.
struct RepositoryOptions: ParsableArguments {
    /// Repository root used for state, config, ignore, and filesystem operations.
    @Option(name: .shortAndLong, help: "The path to the repository root.")
    var path: String = "."
}
