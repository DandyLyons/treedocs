import Foundation
import Yams

/// A missing description prompt candidate enriched with an optional default suggestion.
struct MissingDescriptionCandidate: Equatable {
    /// Relative path in the documented tree.
    let path: String

    /// Whether the path represents a directory entry.
    let isDirectory: Bool

    /// Optional suggested description from the bundled suggestions catalog.
    let suggestedDescription: String?

    /// User-facing path label, with directories made explicit by a trailing slash.
    var displayPath: String {
        isDirectory && !path.hasSuffix("/") ? path + "/" : path
    }
}

/// Provides default description suggestions loaded from YAML.
struct DescriptionSuggestionCatalog: Equatable {
    private let paths: [String: String]
    private let files: [String: String]
    private let directories: [String: String]

    init(paths: [String: String] = [:], files: [String: String] = [:], directories: [String: String] = [:]) {
        self.paths = paths
        self.files = files
        self.directories = directories
    }

    /// Loads the bundled `descriptions-suggestions.yaml` resource.
    static func bundled() throws -> DescriptionSuggestionCatalog {
        guard let url = Bundle.module.url(forResource: "descriptions-suggestions", withExtension: "yaml") else {
            throw TreeDocsError.message("Unable to find bundled descriptions-suggestions.yaml.")
        }

        do {
            let yaml = try String(contentsOf: url, encoding: .utf8)
            return try fromYAML(yaml)
        } catch let error as TreeDocsError {
            throw error
        } catch {
            throw TreeDocsError.message("Failed to load bundled descriptions-suggestions.yaml: \(error.localizedDescription)")
        }
    }

    /// Parses a suggestions catalog from YAML text.
    static func fromYAML(_ yaml: String) throws -> DescriptionSuggestionCatalog {
        guard let raw = try Yams.load(yaml: yaml) else {
            return DescriptionSuggestionCatalog()
        }
        guard let mapping = raw as? [String: Any] else {
            throw TreeDocsError.message("descriptions-suggestions.yaml must contain a mapping at the root.")
        }

        return DescriptionSuggestionCatalog(
            paths: try stringMap(mapping["paths"], key: "paths"),
            files: try stringMap(mapping["files"], key: "files"),
            directories: try stringMap(mapping["directories"], key: "directories")
        )
    }

    /// Returns the best matching suggestion for a documented path.
    func suggestion(for path: String, isDirectory: Bool) -> String? {
        let normalizedPath = normalizePath(path)
        if let exact = suggestion(in: paths, matching: normalizedPath, isDirectory: isDirectory) {
            return exact
        }

        guard let basename = normalizedPath.split(separator: "/").last.map(String.init) else {
            return nil
        }

        if isDirectory {
            return suggestion(in: directories, matching: basename, isDirectory: true)
        }
        return suggestion(in: files, matching: basename, isDirectory: false)
    }

    private func suggestion(in map: [String: String], matching path: String, isDirectory: Bool) -> String? {
        for (rawKey, description) in map {
            let keyRequiresDirectory = rawKey.hasSuffix("/")
            guard keyRequiresDirectory == false || isDirectory else {
                continue
            }
            if normalizePath(rawKey) == path {
                return description
            }
        }
        return nil
    }

    private static func stringMap(_ value: Any?, key: String) throws -> [String: String] {
        guard let value else {
            return [:]
        }
        guard let mapping = value as? [String: Any] else {
            throw TreeDocsError.message("descriptions-suggestions.yaml `\(key)` must be a mapping of strings.")
        }

        var result: [String: String] = [:]
        for (rawKey, rawValue) in mapping {
            guard let description = rawValue as? String else {
                throw TreeDocsError.message("descriptions-suggestions.yaml `\(key).\(rawKey)` must be a string.")
            }
            result[rawKey] = description
        }
        return result
    }

    private func normalizePath(_ raw: String) -> String {
        RelativePath.normalize(raw.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
