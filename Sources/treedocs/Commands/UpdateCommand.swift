import ArgumentParser

struct UpdateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a tree entry's description, references, or link."
    )

    @OptionGroup var options: RepositoryOptions
    @Argument(help: "The path to update.")
    var targetPath: String
    @Argument(help: "An optional replacement description.")
    var description: String?
    @Option(name: .long, parsing: .upToNextOption, help: "Add one or more references.")
    var addReference: [String] = []
    @Option(name: .long, parsing: .upToNextOption, help: "Remove one or more references.")
    var removeReference: [String] = []
    @Option(name: .long, help: "Set or replace the link target.")
    var link: String?
    @Flag(name: .long, help: "Clear any existing link target.")
    var clearLink = false

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
