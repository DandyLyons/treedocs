import Foundation
import JSONSchema
import PathKit
import Yams

/// Validates `treedocs.yaml` documents against the canonical JSON Schema.
struct TreedocsSchemaValidator {
    /// Reads and validates YAML from disk.
    ///
    /// - Parameter path: The `treedocs.yaml` path to validate.
    /// - Throws: `TreeDocsError` when the file cannot be decoded or validation fails.
    func validateFile(at path: Path) throws {
        let data = try path.read()
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw TreeDocsError.message("Failed to decode treedocs.yaml at \(path.string) as UTF-8.")
        }
        try validate(yaml: yaml)
    }

    /// Validates YAML text against the canonical schema.
    ///
    /// - Parameters:
    ///   - yaml: YAML document text.
    ///   - schemaPath: Optional explicit schema path for tests or tooling. When omitted, the bundled schema is used.
    /// - Throws: `TreeDocsError` when YAML is structurally invalid or fails schema validation.
    func validate(yaml: String, schemaPath: Path? = nil) throws {
        guard let parsed = try Yams.load(yaml: yaml) else {
            throw TreeDocsError.message("Schema validation failed: # must be an object with project, signature, and tree.")
        }

        let schemaVersion = try schemaVersion(from: parsed)
        let instanceJSON = try jsonString(from: parsed, label: "treedocs.yaml")
        let schemaJSON = try loadSchema(for: schemaVersion, from: schemaPath)
        let schema = try Schema(instance: schemaJSON)
        let result = try schema.validate(instance: instanceJSON)
        guard result.isValid else {
            throw TreeDocsError.message("Schema validation failed: \(formatErrors(result.errors))")
        }
    }

    private func schemaVersion(from parsed: Any) throws -> String {
        guard let mapping = parsed as? [String: Any] else {
            throw TreeDocsError.message("Schema validation failed: # must be an object with project, signature, and tree.")
        }

        guard let version = parseString(mapping["schema_version"]) else {
            throw TreeDocsError.message("Schema validation failed: missing required root schema_version.")
        }

        guard TreedocsSchemaMetadata.isSupported(version) else {
            throw TreeDocsError.message(unsupportedSchemaVersionMessage(version))
        }

        return version
    }

    private func loadSchema(for version: String, from explicitPath: Path?) throws -> String {
        if let explicitPath, explicitPath.exists {
            return try readUTF8(explicitPath)
        }

        return try bundledSchemaJSON(for: version)
    }

    private func bundledSchemaJSON(for version: String) throws -> String {
        let resourceName = try bundledSchemaResourceName(for: version)

        guard let url = Bundle.module.url(forResource: resourceName, withExtension: "json") else {
            throw TreeDocsError.message("Unable to find bundled canonical schema for schema_version \"\(version)\".")
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw TreeDocsError.message("Failed to read bundled canonical schema for schema_version \"\(version)\": \(error.localizedDescription)")
        }
    }

    private func bundledSchemaResourceName(for version: String) throws -> String {
        switch version {
        case TreedocsSchemaMetadata.v0_1_0:
            return "treedocs-0.1.0.schema"
        case TreedocsSchemaMetadata.currentVersion:
            return "treedocs-0.2.0.schema"
        default:
            throw TreeDocsError.message(unsupportedSchemaVersionMessage(version))
        }
    }

    private func unsupportedSchemaVersionMessage(_ version: String) -> String {
        let supported = TreedocsSchemaMetadata.supportedVersions.joined(separator: ", ")
        return "Unsupported treedocs.yaml schema_version \"\(version)\". This CLI supports: \(supported). Upgrade treedocs or use a supported schema version."
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
            return "document does not match a bundled treedocs schema."
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
