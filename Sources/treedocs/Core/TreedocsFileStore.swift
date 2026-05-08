import Foundation
import PathKit

struct TreedocsFileStore {
    func load(at path: Path) throws -> TreedocsFile {
        guard path.exists else {
            throw TreeDocsError.message("Missing treedocs state file at \(path.string). Run `treedocs init` first.")
        }
        return try TreedocsFile.load(from: try path.read())
    }

    func save(_ file: TreedocsFile, at path: Path) throws {
        try file.toYAMLString().write(to: path.url, atomically: true, encoding: .utf8)
    }
}
