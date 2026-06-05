import ArgumentParser

/// Implements the `treedocs update` command.
struct UpdateCommand: ParsableCommand {
    /// Command metadata for editing documentation metadata on one tree entry.
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a tree entry's description, references, or link."
    )

    /// Shared repository selection options.
    @OptionGroup var options: RepositoryOptions

    /// Documented tree path whose metadata should be changed.
    @Argument(help: "The path to update.")
    var targetPath: String

    /// Replacement description text, when the update changes the entry description.
    @Argument(help: "An optional replacement description.")
    var description: String?

    /// References to append to the entry without duplicating existing values.
    @Option(name: .long, parsing: .upToNextOption, help: "Add one or more references.")
    var addReference: [String] = []

    /// References to remove from the entry.
    @Option(name: .long, parsing: .upToNextOption, help: "Remove one or more references.")
    var removeReference: [String] = []

    /// Replacement `_link` target for the entry.
    @Option(name: .long, help: "Set or replace the link target.")
    var link: String?

    /// Whether any existing `_link` target should be removed.
    @Flag(name: .long, help: "Clear any existing link target.")
    var clearLink = false

    /// Applies a description, reference, or link update to a documented path.
    mutating func run() throws {
        if description == nil && addReference.isEmpty && removeReference.isEmpty && link == nil && !clearLink {
            throw ValidationError("No update requested. Provide a description or one of the reference/link flags.")
        }

        let file = try TreedocsService().update(
            at: options.path,
            path: targetPath,
            description: description,
            addReferences: addReference,
            removeReferences: removeReference,
            link: link,
            clearLink: clearLink
        )
        print("Updated \(targetPath) (\(file.signature ?? "no signature"))")
    }
}
