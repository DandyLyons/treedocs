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
        if let root = parsed as? [String: Any], let overrides = root["overrides"] as? [String: Any] {
            _ = try FolderDocumentationSourceSelection.parse(overrides["documentation_sources"])
        }
        try validateSupportedFormatsAndReferences(in: parsed)
        let instance = try normalize(parsed, path: "#")
        let schemaJSON = try loadSchema(for: schemaVersion, from: schemaPath)
        guard let schemaData = schemaJSON.data(using: .utf8),
              let schema = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any] else {
            throw TreeDocsError.message("Failed to decode the bundled treedocs JSON Schema.")
        }
        guard let normalizedSchema = removingFormatAnnotations(from: schema) as? [String: Any] else {
            throw TreeDocsError.message("Failed to normalize the bundled treedocs JSON Schema.")
        }
        let result = try JSONSchema.validate(instance, schema: normalizedSchema)
        guard result.valid else {
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
        case TreedocsSchemaMetadata.stagingVersion:
            return "treedocs-0.3.0-WIP.schema"
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

    /// JSONSchema.swift reports unsupported format annotations as validation failures. Treedocs uses
    /// only `format: date`, so validate that contract directly and remove annotations before passing
    /// the schema to the general validator.
    private func validateSupportedFormatsAndReferences(in parsed: Any) throws {
        if let root = parsed as? [String: Any],
           let project = root["project"] as? [String: Any],
           let date = project["last_updated"] as? String {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            guard date.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil,
                  formatter.date(from: date) != nil else {
                throw TreeDocsError.message("Schema validation failed: #/project/last_updated: must be a valid YYYY-MM-DD date.")
            }
        }

        if let root = parsed as? [String: Any], let tree = root["tree"] {
            try validateReferences(in: tree, path: "#/tree")
        }
    }

    private func validateReferences(in value: Any, path: String) throws {
        if let mapping = value as? [String: Any] {
            for key in ["_references", "references"] {
                if let references = mapping[key] as? [Any] {
                    for (index, item) in references.enumerated() {
                        guard let reference = item as? String, isValidReference(reference) else {
                            throw TreeDocsError.message("Schema validation failed: \(path)/\(key)/\(index): must be a local path, HTTPS URL, or Markdown link.")
                        }
                    }
                }
            }
            for (key, child) in mapping {
                try validateReferences(in: child, path: "\(path)/\(key)")
            }
        } else if let array = value as? [Any] {
            for (index, child) in array.enumerated() {
                try validateReferences(in: child, path: "\(path)/\(index)")
            }
        }
    }

    private func isValidReference(_ reference: String) -> Bool {
        if reference.hasPrefix("https://"), !reference.contains(where: \.isWhitespace) {
            return true
        }
        if reference.range(of: "^\\[[^\\]\\n]+\\]\\((?:https://\\S+|(?!(?:[A-Za-z][A-Za-z0-9+.-]*:))(?=.*\\S)[^)\\n]+)\\)$", options: .regularExpression) != nil {
            return true
        }
        return reference.range(of: "^(?!\\[)(?![A-Za-z][A-Za-z0-9+.-]*:)(?=.*\\S)[^\\n]+$", options: .regularExpression) != nil
    }

    private func removingFormatAnnotations(from value: Any) -> Any {
        if let mapping = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: mapping.compactMap { key, child in
                key == "format" ? nil : (key, removingFormatAnnotations(from: child))
            })
        }
        if let array = value as? [Any] {
            return array.map(removingFormatAnnotations)
        }
        return value
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
        let errors = errors ?? []
        guard !errors.isEmpty else {
            return "document does not match a bundled treedocs schema."
        }
        return errors.map { error in
            let location = error.instanceLocation.path.isEmpty ? "#" : "#\(error.instanceLocation.path)"
            return "\(location): \(error.description)"
        }.joined(separator: "; ")
    }
}
