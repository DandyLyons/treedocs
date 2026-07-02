import ArgumentParser

/// Implements the implicit and explicit `treedocs show` command.
struct ShowCommand: ParsableCommand {
    /// Command metadata for rendering one documented path.
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Render a documented path with inline descriptions.",
        discussion: "Displays the documented tree rooted at the given path."
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// Documented path to render; shorthand root invocations are rewritten to this command.
    @Argument(help: "The documented path to render.")
    var targetPath: String

    /// Whether rendering should proceed without first reporting stale state warnings.
    @Flag(name: .long, help: "Skip validation before rendering.")
    var noCheck = false

    /// Whether long descriptions should be rendered without truncation.
    @Flag(name: [.customShort("f"), .long], help: "Render full descriptions instead of truncating them.")
    var fullDescriptions = false

    /// Renders the requested path, optionally checking for drift first.
    mutating func run() throws {
        try Self.render(options: options, targetPath: targetPath, noCheck: noCheck, fullDescriptions: fullDescriptions)
    }

    /// Prints rendered documentation for a repository path.
    static func render(options: RepositoryOptions, targetPath: String, noCheck: Bool, fullDescriptions: Bool) throws {
        let output = try TreedocsService().show(at: options.path, path: targetPath, checkFirst: !noCheck, fullDescriptions: fullDescriptions)
        print(output)
    }
}
