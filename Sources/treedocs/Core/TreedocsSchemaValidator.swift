import Foundation
import JSONSchema
import PathKit
import Yams

/// Validates `treedocs.yaml` documents against the canonical JSON Schema.
struct TreedocsSchemaValidator {
    /// Reads and validates YAML from disk.
    ///
    /// - Parameter path: The `treedocs.yaml` path to validate.
    /// - Throws: `TreeDocsError` when the file cannot be decoded, the schema cannot be found, or validation fails.
    func validateFile(at path: Path) throws {
        let data = try path.read()
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw TreeDocsError.message("Failed to decode treedocs.yaml at \(path.string) as UTF-8.")
        }
        try validate(yaml: yaml, schemaPath: schemaPath(for: path.parent()))
    }

    /// Validates YAML text against the canonical schema.
    ///
    /// - Parameters:
    ///   - yaml: YAML document text.
    ///   - schemaPath: Optional explicit schema path. When omitted, the validator searches upward from the current directory.
    /// - Throws: `TreeDocsError` when YAML is structurally invalid or fails schema validation.
    func validate(yaml: String, schemaPath: Path? = nil) throws {
        guard let parsed = try Yams.load(yaml: yaml) else {
            throw TreeDocsError.message("Schema validation failed: # must be an object with project, signature, and tree.")
        }

        let instanceJSON = try jsonString(from: parsed, label: "treedocs.yaml")
        let schemaJSON = try loadSchema(from: schemaPath)
        let schema = try Schema(instance: schemaJSON)
        let result = try schema.validate(instance: instanceJSON)
        guard result.isValid else {
            throw TreeDocsError.message("Schema validation failed: \(formatErrors(result.errors))")
        }
    }

    private func loadSchema(from explicitPath: Path?) throws -> String {
        if let explicitPath, explicitPath.exists {
            return try readUTF8(explicitPath)
        }

        if let discovered = discoverSchemaPath(), discovered.exists {
            return try readUTF8(discovered)
        }

        throw TreeDocsError.message("Unable to find canonical schema at DOCS/treedocs.schema.json.")
    }

    private func schemaPath(for root: Path) -> Path? {
        let candidate = root + Path("DOCS/treedocs.schema.json")
        return candidate.exists ? candidate : nil
    }

    private func discoverSchemaPath() -> Path? {
        var current = Path(FileManager.default.currentDirectoryPath).absolute()
        while true {
            let candidate = current + Path("DOCS/treedocs.schema.json")
            if candidate.exists {
                return candidate
            }

            let parent = current.parent()
            if parent == current {
                return nil
            }
            current = parent
        }
    }

    private func readUTF8(_ path: Path) throws -> String {
        let data = try path.read()
        guard let string = String(data: data, encoding: .utf8) else {
            throw TreeDocsError.message("Failed to decode schema at \(path.string) as UTF-8.")
        }
        return string
    }

    private func jsonString(from value: Any, label: String) throws -> String {
        let normalized = try normalize(value, path: "#")
        let data = try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw TreeDocsError.message("Failed to encode \(label) as JSON for schema validation.")
        }
        return string
    }

    private func normalize(_ value: Any, path: String) throws -> Any {
        switch value {
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let double as Double:
            return double
        case let number as NSNumber:
            return number
        case let array as [Any]:
            return try array.enumerated().map { index, item in
                try normalize(item, path: "\(path)/\(index)")
            }
        case let mapping as [String: Any]:
            var normalized: [String: Any] = [:]
            for (key, item) in mapping {
                normalized[key] = try normalize(item, path: "\(path)/\(key)")
            }
            return normalized
        case Optional<Any>.none:
            return NSNull()
        default:
            throw TreeDocsError.message("Schema validation failed: unsupported YAML value at \(path).")
        }
    }

    private func formatErrors(_ errors: [ValidationError]?) -> String {
        let flattened = flatten(errors ?? [])
        guard !flattened.isEmpty else {
            return "document does not match DOCS/treedocs.schema.json."
        }
        return flattened.map { error in
            "\(error.instanceLocation): \(error.message)"
        }.joined(separator: "; ")
    }

    private func flatten(_ errors: [ValidationError]) -> [ValidationError] {
        errors.flatMap { error -> [ValidationError] in
            if let nested = error.errors, !nested.isEmpty {
                return flatten(nested)
            }
            return [error]
        }
    }
}
