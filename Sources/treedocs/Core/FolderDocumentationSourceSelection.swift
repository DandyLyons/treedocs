import Foundation

/// Selects exactly one documentation filename for each owned folder.
///
/// Shared by filesystem discovery and stub creation. Overrides apply only to their exact folder;
/// every other folder uses `README.md`. Selection does not check file existence or ownership.
/// See <doc:GettingStarted> for the user-facing configuration and creation workflow.
struct FolderDocumentationSourceSelection {
    /// Validated folder-to-filename mapping, keyed by `.` or a relative directory path ending in `/`.
    var overrides: [String: String] = [:]

    /// Returns the exact-folder override or the implicit `README.md` default, without inheritance.
    ///
    /// - Parameter directory: Scanner-relative directory path without a trailing slash, or an empty
    ///   string for the repository root.
    func filename(for directory: String) -> String {
        overrides[directory.isEmpty ? "." : directory + "/"] ?? "README.md"
    }

    /// Whether the folder explicitly selects a source, even when that filename is `README.md`.
    ///
    /// Explicit sources require diagnostics when missing or excluded; implicit sources may be absent.
    /// - Parameter directory: Scanner-relative directory path without a trailing slash, or an empty
    ///   string for the repository root.
    func isExplicit(_ directory: String) -> Bool {
        overrides[directory.isEmpty ? "." : directory + "/"] != nil
    }

    /// Validates the raw YAML `documentation_sources` mapping without accessing the filesystem.
    ///
    /// Folder keys use `.` for the root or relative paths ending in `/`, with no dot traversal or
    /// empty components. Values must be nonblank filenames without directory components.
    ///
    /// - Parameter value: The configuration field's decoded YAML value, or `nil` when omitted.
    /// - Returns: The validated mapping, preserving an explicit empty mapping; `nil` when omitted.
    /// - Throws: ``TreeDocsError`` when the mapping shape, a folder key, or a filename is invalid.
    static func parse(_ value: Any?) throws -> [String: String]? {
        guard let value else { return nil }
        guard let mapping = value as? [String: String] else {
            throw TreeDocsError.message("documentation_sources must map exact folder paths to filenames.")
        }
        for (directory, filename) in mapping {
            let components = directory.dropLast().split(separator: "/", omittingEmptySubsequences: false)
            guard directory == "." || (directory.hasSuffix("/") && !directory.hasPrefix("/")
                && !directory.contains("\\") && !directory.contains("\n") && !directory.contains("\r")
                && !directory.contains("\0") && components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })),
                !filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                filename != ".", filename != "..", !filename.contains("/"), !filename.contains("\\"),
                !filename.contains("\n"), !filename.contains("\r"), !filename.contains("\0") else {
                throw TreeDocsError.message("Invalid documentation_sources entry '\(directory): \(filename)'. Use '.' or an exact relative folder path ending in '/', and a filename without directory components.")
            }
        }
        return mapping
    }
}
