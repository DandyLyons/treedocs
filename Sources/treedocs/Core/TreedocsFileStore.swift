import Foundation
import PathKit

/// Reads and writes `treedocs.yaml` state files.
///
/// The store is the filesystem boundary for serialized treedocs state. Parsing and serialization are
/// delegated to `TreedocsFile` so callers receive typed models instead of raw YAML.
struct TreedocsFileStore {
    var validator = TreedocsSchemaValidator()

    /// Loads a treedocs state file from disk.
    ///
    /// - Parameter path: The expected `treedocs.yaml` path.
    /// - Returns: The parsed state model.
    /// - Throws: `TreeDocsError` when the file is missing, plus file read or YAML parsing errors.
    func load(at path: Path) throws -> TreedocsFile {
        guard path.exists else {
            throw TreeDocsError.message("Missing treedocs state file at \(path.string). Run `treedocs init` first.")
        }
        try validator.validateFile(at: path)
        let file = try loadWithoutSchemaValidation(at: path)
        for warning in TreedocsSchemaMetadata.deprecationWarnings(for: file.schemaVersion) {
            fputs("Warning: \(warning)\n", stderr)
        }
        return file
    }

    /// Loads a treedocs state file without running JSON Schema validation.
    ///
    /// This is used by `check` after schema errors have already been captured for reporting.
    func loadWithoutSchemaValidation(at path: Path) throws -> TreedocsFile {
        return try TreedocsFile.load(from: try path.read())
    }

    /// Saves a treedocs state file to disk.
    ///
    /// The file is written atomically as UTF-8 YAML with the managed YAML language-server schema
    /// header and then validated against the canonical schema.
    ///
    /// - Parameters:
    ///   - file: The state model to serialize.
    ///   - path: The destination `treedocs.yaml` path.
    /// - Throws: YAML serialization or filesystem write errors.
    func save(_ file: TreedocsFile, at path: Path) throws {
        try serializedDocument(for: file).write(to: path.url, atomically: true, encoding: .utf8)
        try validator.validateFile(at: path)
    }

    /// Serializes a complete managed `treedocs.yaml` document.
    func serializedDocument(for file: TreedocsFile) throws -> String {
        let header = TreedocsSchemaMetadata.languageServerHeader(for: file.schemaVersion)
        return "\(header)\n\(try file.toYAMLString())"
    }
}
