import ArgumentParser

struct RepositoryOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "The path to the repository root.")
    var path: String = "."
}
