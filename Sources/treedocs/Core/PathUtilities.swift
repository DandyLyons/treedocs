import Foundation
import PathKit

/// Represents user-facing errors emitted by treedocs commands and services.
///
/// `TreeDocsError` wraps validation and domain failures in localized descriptions that can be
/// printed directly by command-line entry points.
enum TreeDocsError: Error, LocalizedError {
    /// A user-readable error message.
    case message(String)

    /// The localized description surfaced by Swift error reporting.
    var errorDescription: String? {
        switch self {
        case let .message(message):
            return message
        }
    }
}

/// Adds string-normalization helpers used while parsing user input and YAML.
///
/// These helpers keep optional text fields consistent by treating empty or whitespace-only values as
/// missing values.
extension String {
    /// Returns trimmed text, or `nil` when the trimmed string is empty.
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Normalizes and resolves repository-relative paths used in the documentation tree.
///
/// Paths in `treedocs.yaml` are stored with forward slashes and without dot segments. This type keeps
/// command input, YAML keys, and `_link` targets in that canonical form.
enum RelativePath {
    /// Normalizes a raw path string.
    ///
    /// Backslashes are converted to slashes, empty components and `.` are removed, and `..` removes
    /// the previous component when possible.
    ///
    /// - Parameter raw: The raw path string to normalize.
    /// - Returns: A slash-separated relative path with dot segments resolved.
    static func normalize(_ raw: String) -> String {
        let replaced = raw.replacingOccurrences(of: "\\", with: "/")
        let components = normalizeComponents(replaced.split(separator: "/").map(String.init))
        return components.joined(separator: "/")
    }

    /// Splits a raw path into normalized components.
    ///
    /// This is the component-level equivalent of `normalize(_:)` and is useful when callers need to
    /// traverse nested tree dictionaries.
    ///
    /// - Parameter raw: The raw path string to split.
    /// - Returns: Normalized path components.
    static func components(for raw: String) -> [String] {
        normalizeComponents(raw.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init))
    }

    /// Resolves a link target from the current documented path.
    ///
    /// Targets beginning with `./` or `../` are resolved relative to the current path's containing
    /// directory. Other targets are normalized as repository-relative paths.
    ///
    /// - Parameters:
    ///   - raw: The raw link target.
    ///   - currentPath: The path containing the link.
    /// - Returns: A normalized repository-relative path.
    static func resolve(_ raw: String, from currentPath: String) -> String {
        if raw.hasPrefix("./") || raw.hasPrefix("../") {
            let baseComponents = components(for: currentPath).dropLast()
            let combined = Array(baseComponents) + raw.split(separator: "/").map(String.init)
            return normalizeComponents(combined).joined(separator: "/")
        }

        return normalize(raw)
    }

    /// Applies dot-segment normalization to path components.
    ///
    /// Parent components at the beginning of a path are ignored instead of escaping above the
    /// repository root.
    ///
    /// - Parameter rawComponents: Path components before normalization.
    /// - Returns: Components with empty, `.`, and resolvable `..` segments removed.
    private static func normalizeComponents(_ rawComponents: [String]) -> [String] {
        var result: [String] = []
        for component in rawComponents {
            switch component {
            case "", ".":
                continue
            case "..":
                if !result.isEmpty {
                    result.removeLast()
                }
            default:
                result.append(component)
            }
        }
        return result
    }
}

/// Stores resolved paths for repository-level treedocs files.
///
/// `RepositoryPaths` validates the repository root once and derives the locations of the state file,
/// project configuration, project ignore file, and `.gitignore` from that root.
struct RepositoryPaths {
    /// The validated absolute repository root path.
    let root: Path

    /// Validates and stores an absolute repository root path.
    ///
    /// - Parameter rootPath: The path that should identify a repository directory.
    /// - Throws: `TreeDocsError` when the path does not exist or is not a directory.
    init(rootPath: String) throws {
        let resolved = Path(rootPath).absolute()
        guard resolved.exists else {
            throw TreeDocsError.message("Path does not exist: \(resolved.string)")
        }
        guard resolved.isDirectory else {
            throw TreeDocsError.message("Path is not a directory: \(resolved.string)")
        }
        root = resolved
    }

    /// The repository-local state file managed by treedocs.
    var stateFile: Path { root + Path("treedocs.yaml") }

    /// Project-level configuration loaded after global configuration.
    var projectConfig: Path { root + Path(".treedocs/config.yaml") }

    /// Project-level ignore file loaded in addition to configured excludes and `.gitignore`.
    var projectIgnore: Path { root + Path(".treedocs/.treedocs_ignore") }

    /// Repository `.gitignore` file used when `use_gitignore` is enabled.
    var gitignore: Path { root + Path(".gitignore") }
}
