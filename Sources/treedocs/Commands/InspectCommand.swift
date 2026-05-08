import ArgumentParser

struct InspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Show documentation details for a documented path."
    )

    @OptionGroup var options: RepositoryOptions
    @Argument(help: "The path to inspect.")
    var targetPath: String
    @Flag(help: "Render child entries recursively when the target is a directory.")
    var recursive = false

    mutating func run() throws {
        let report = try TreedocsService().inspect(at: options.path, path: targetPath, recursive: recursive)
        print("Path: \(report.path)")
        print("Type: \(report.entry.isDirectory ? "directory" : "file")")
        print("Description: \(report.entry.description ?? "<missing>")")

        if !report.entry.references.isEmpty {
            print("References:")
            for reference in report.entry.references {
                print("- \(reference)")
            }
        }

        switch report.linkResolution {
        case .none:
            break
        case let .external(url):
            print("Link: external -> \(url)")
        case let .resolved(path, chain, _):
            print("Link: \(chain.joined(separator: " -> "))")
            print("Resolved: \(path)")
        case let .broken(target, chain):
            print("Link: \(chain.joined(separator: " -> "))")
            print("Broken target: \(target)")
        case let .cycle(chain):
            print("Link cycle: \(chain.joined(separator: " -> "))")
        }

        if let recursiveOutput = report.recursiveOutput {
            print("Tree:")
            print(recursiveOutput)
        }
    }
}
