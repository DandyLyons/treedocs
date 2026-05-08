import Foundation
import PathKit

enum TreeDocsError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message):
            return message
        }
    }
}

extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum RelativePath {
    static func normalize(_ raw: String) -> String {
        let replaced = raw.replacingOccurrences(of: "\\", with: "/")
        let components = normalizeComponents(replaced.split(separator: "/").map(String.init))
        return components.joined(separator: "/")
    }

    static func components(for raw: String) -> [String] {
        normalizeComponents(raw.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init))
    }

    static func resolve(_ raw: String, from currentPath: String) -> String {
        if raw.hasPrefix("./") || raw.hasPrefix("../") {
            let baseComponents = components(for: currentPath).dropLast()
            let combined = Array(baseComponents) + raw.split(separator: "/").map(String.init)
            return normalizeComponents(combined).joined(separator: "/")
        }

        return normalize(raw)
    }

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

struct RepositoryPaths {
    let root: Path

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

    var stateFile: Path { root + Path("treedocs.yaml") }
    var projectConfig: Path { root + Path(".treedocs/config.yaml") }
    var projectIgnore: Path { root + Path(".treedocs/.treedocs_ignore") }
    var gitignore: Path { root + Path(".gitignore") }
}
