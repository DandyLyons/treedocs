import ArgumentParser
import Foundation
import PathKit
import Yams

@main
struct TreeDocs: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "treedocs",
        abstract: "Generate and maintain a YAML-based architectural map of a repository."
    )

    @Option(name: .shortAndLong, help: "The path to the repository root to map.")
    var path: String = "."

    mutating func run() throws {
        let root = Path(path).absolute()
        guard root.exists else {
            throw ValidationError("Path does not exist: \(root)")
        }
        print("Scanning \(root) …")
    }
}
