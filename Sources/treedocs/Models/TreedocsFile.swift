import Foundation
import Yams

/// Shared schema metadata for generated `treedocs.yaml` files.
enum TreedocsSchemaMetadata {
    /// The current treedocs file-format schema version.
    static let currentVersion = "0.1.0"

    /// Returns the public JSON Schema URL for a schema version.
    static func schemaURL(for version: String) -> String {
        "https://dandylyons.github.io/treedocs/schemas/\(version)/treedocs.schema.json"
    }

    /// Returns the managed YAML language-server declaration for a schema version.
    static func languageServerHeader(for version: String) -> String {
        "# yaml-language-server: $schema=\(schemaURL(for: version))"
    }
}

/// Stores project metadata from `treedocs.yaml`.
///
/// `ProjectMetadata` models the root `project` section. Known fields are exposed directly while
/// unknown scalar-like keys are preserved in `extra` so round-tripping does not discard user metadata.
struct ProjectMetadata: Equatable {
    /// The project name stored under `project.name`.
    var name: String?

    /// The project version stored under `project.version`.
    var version: String?

    /// The last update date stored under `project.last_updated`.
    var lastUpdated: String?

    /// Additional project keys not modeled by first-class properties.
    var extra: [String: String]

    /// Creates project metadata.
    ///
    /// Empty or whitespace-only known string fields are normalized to `nil`. Extra fields are stored
    /// exactly as provided.
    ///
    /// - Parameters:
    ///   - name: The project name.
    ///   - version: The project version.
    ///   - lastUpdated: The last update date.
    ///   - extra: Additional project metadata to preserve.
    init(name: String? = nil, version: String? = nil, lastUpdated: String? = nil, extra: [String: String] = [:]) {
        self.name = name?.trimmedNilIfEmpty
        self.version = version?.trimmedNilIfEmpty
        self.lastUpdated = lastUpdated?.trimmedNilIfEmpty
        self.extra = extra
    }

    /// A Boolean value indicating whether the metadata section has no values to serialize.
    var isEmpty: Bool {
        name == nil && version == nil && lastUpdated == nil && extra.isEmpty
    }

    /// Returns a metadata value by its YAML key.
    ///
    /// Known keys are resolved from their first-class properties. Other keys are looked up in
    /// `extra`.
    ///
    /// - Parameter key: The YAML metadata key to read.
    /// - Returns: The value for `key`, or `nil` when no value exists.
    subscript(key: String) -> String? {
        switch key {
        case "name":
            return name
        case "version":
            return version
        case "last_updated":
            return lastUpdated
        default:
            return extra[key]
        }
    }

    /// Parses project metadata from YAML.
    ///
    /// A string scalar is accepted as shorthand for a project name. Mapping values populate known
    /// fields and preserve unknown string, Boolean, and integer values as strings in `extra`.
    ///
    /// - Parameter value: The raw YAML value from the `project` key.
    /// - Returns: Parsed metadata, or `nil` when the value is absent or unsupported.
    static func fromYAML(_ value: Any?) -> ProjectMetadata? {
        guard let mapping = value as? [String: Any] else {
            if let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ProjectMetadata(name: string)
            }
            return nil
        }

        let knownKeys = Set(["name", "version", "last_updated"])
        var extra: [String: String] = [:]
        for (key, value) in mapping {
            guard !knownKeys.contains(key) else { continue }
            if let stringValue = parseString(value) ?? (value as? Bool).map(String.init) ?? (value as? Int).map(String.init) {
                extra[key] = stringValue
            }
        }

        return ProjectMetadata(
            name: parseString(mapping["name"]),
            version: parseString(mapping["version"]),
            lastUpdated: parseString(mapping["last_updated"]),
            extra: extra
        )
    }

    /// Converts project metadata to YAML.
    ///
    /// Known keys are emitted first and extra keys are emitted in sorted order for deterministic
    /// output.
    ///
    /// - Returns: A YAML-compatible mapping for the `project` section.
    func toYAMLValue() -> [String: Any] {
        var mapping: [String: Any] = [:]
        if let name { mapping["name"] = name }
        if let version { mapping["version"] = version }
        if let lastUpdated { mapping["last_updated"] = lastUpdated }
        for (key, value) in extra.sorted(by: { $0.key < $1.key }) {
            mapping[key] = value
        }
        return mapping
    }
}

/// Stores description and reference metadata for a documented entry.
///
/// Documentation can be serialized as a compact string when it contains only a description, or as a
/// mapping when references are present.
struct EntryDocumentation: Equatable {
    /// Human-readable documentation for an entry.
    var description: String?

    /// External or internal references associated with the entry.
    var references: [String]

    /// Creates entry documentation.
    ///
    /// Description text is trimmed, while references are preserved in their supplied order.
    ///
    /// - Parameters:
    ///   - description: Optional human-readable documentation text.
    ///   - references: References associated with the entry.
    init(description: String? = nil, references: [String] = []) {
        self.description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.references = references
    }

    /// A Boolean value indicating whether the documentation has no serializable content.
    var isEmpty: Bool {
        description == nil && references.isEmpty
    }

    /// Parses entry documentation from YAML.
    ///
    /// Strings are interpreted as simple descriptions. Mappings may contain `description` and
    /// `references` keys. A missing value means the entry has no documentation.
    ///
    /// - Parameter value: The raw YAML value for a leaf entry or directory `_doc` key.
    /// - Returns: Parsed documentation, or `nil` when no documentation exists.
    /// - Throws: `TreeDocsError` when the YAML value is neither a string nor a mapping.
    static func fromYAML(_ value: Any?) throws -> EntryDocumentation? {
        guard let value else { return nil }

        if let string = value as? String {
            return EntryDocumentation(description: string)
        }

        guard let mapping = value as? [String: Any] else {
            throw TreeDocsError.message("Invalid documentation entry in treedocs.yaml.")
        }

        return EntryDocumentation(
            description: parseString(mapping["description"]),
            references: parseStringArray(mapping["references"]) ?? []
        )
    }

    /// Converts documentation to YAML.
    ///
    /// Documentation with only a description uses the compact scalar form. Documentation with
    /// references uses the mapping form required by the schema.
    ///
    /// - Returns: A YAML-compatible string or mapping.
    func toYAMLValue() -> Any {
        if references.isEmpty, let description {
            return description
        }

        var mapping: [String: Any] = [:]
        if let description {
            mapping["description"] = description
        }
        if !references.isEmpty {
            mapping["references"] = references
        }
        return mapping
    }
}

/// Represents a documented file or directory in the tree.
///
/// `TreeEntry` is the recursive model used by the `tree` section. Directories store children and may
/// use `_doc` metadata, while file entries are leaves. Both entry kinds can point at another entry or
/// URL through `_link`.
struct TreeEntry: Equatable {
    /// The entry's optional description and references.
    var documentation: EntryDocumentation?

    /// The optional `_link` target for this entry.
    var link: String?

    /// Child entries keyed by path component for directory entries.
    var children: [String: TreeEntry]

    /// A Boolean value indicating whether this entry represents a directory.
    var isDirectory: Bool

    /// Creates a tree entry.
    ///
    /// Empty documentation and empty link values are normalized to `nil`. Callers are responsible for
    /// keeping `children` and `isDirectory` consistent.
    ///
    /// - Parameters:
    ///   - documentation: Optional entry documentation.
    ///   - link: Optional `_link` target.
    ///   - children: Child entries for directory entries.
    ///   - isDirectory: Whether the entry represents a directory.
    init(
        documentation: EntryDocumentation? = nil,
        link: String? = nil,
        children: [String: TreeEntry] = [:],
        isDirectory: Bool = false
    ) {
        self.documentation = documentation?.isEmpty == true ? nil : documentation
        self.link = link?.trimmedNilIfEmpty
        self.children = children
        self.isDirectory = isDirectory
    }

    /// Creates a tree entry from simple documentation fields.
    ///
    /// This convenience initializer is used by the scanner and tests when constructing entries from a
    /// description and reference list instead of an `EntryDocumentation` value.
    ///
    /// - Parameters:
    ///   - description: Optional documentation text.
    ///   - references: References associated with the entry.
    ///   - link: Optional `_link` target.
    ///   - children: Child entries for directory entries.
    ///   - isDirectory: Whether the entry represents a directory.
    init(description: String?, references: [String] = [], link: String? = nil, children: [String: TreeEntry] = [:], isDirectory: Bool = false) {
        self.init(
            documentation: EntryDocumentation(description: description, references: references),
            link: link,
            children: children,
            isDirectory: isDirectory
        )
    }

    /// The entry's description text, if present.
    var description: String? {
        documentation?.description
    }

    /// The entry's references, or an empty array when it has no documentation.
    var references: [String] {
        documentation?.references ?? []
    }

    /// A Boolean value indicating whether the entry has one or more references.
    var hasReferences: Bool {
        !references.isEmpty
    }

    /// A Boolean value indicating whether the entry should be reported as missing documentation.
    var needsDescription: Bool {
        (description?.isEmpty ?? true) && link == nil
    }

    /// Parses a tree entry from YAML.
    ///
    /// String values are compact leaf descriptions. Mappings become directories when they include
    /// `_doc` or child keys; otherwise they are parsed as leaf documentation plus optional `_link`.
    /// Child keys may contain slash-separated paths and are inserted into nested dictionaries.
    ///
    /// - Parameter value: The raw YAML value for a tree entry.
    /// - Returns: A parsed tree entry.
    /// - Throws: `TreeDocsError` when the value cannot be interpreted as a valid tree entry.
    static func fromYAML(_ value: Any) throws -> TreeEntry {
        if let string = value as? String {
            return TreeEntry(description: string)
        }

        guard let mapping = value as? [String: Any] else {
            throw TreeDocsError.message("Invalid tree entry in treedocs.yaml.")
        }

        let reservedLeafKeys: Set<String> = ["description", "references", "_link"]
        let hasDirectoryMarker = mapping.keys.contains("_doc")
        let childKeys = mapping.keys.filter { !reservedLeafKeys.contains($0) && $0 != "_doc" }
        let isDirectory = hasDirectoryMarker || !childKeys.isEmpty

        if isDirectory {
            var children: [String: TreeEntry] = [:]
            for childKey in childKeys {
                let entry = try TreeEntry.fromYAML(mapping[childKey] as Any)
                TreeOperations.insert(entry: entry, at: RelativePath.components(for: childKey), into: &children)
            }

            return TreeEntry(
                documentation: try EntryDocumentation.fromYAML(mapping["_doc"]),
                link: parseString(mapping["_link"]),
                children: children,
                isDirectory: true
            )
        }

        return TreeEntry(
            documentation: try EntryDocumentation.fromYAML(mapping),
            link: parseString(mapping["_link"]),
            children: [:],
            isDirectory: false
        )
    }

    /// Converts a tree entry to YAML.
    ///
    /// File entries with only a description use the compact scalar form. Directories emit `_doc`,
    /// `_link`, and sorted child keys when present.
    ///
    /// - Returns: A YAML-compatible scalar or mapping for the entry.
    func toYAMLValue() -> Any {
        if isDirectory {
            var mapping: [String: Any] = [:]
            if let documentation, !documentation.isEmpty {
                mapping["_doc"] = documentation.toYAMLValue()
            }
            if let link {
                mapping["_link"] = link
            }
            for key in children.keys.sorted() {
                mapping[key] = children[key]?.toYAMLValue()
            }
            return mapping
        }

        if link == nil, references.isEmpty, let description {
            return description
        }

        var mapping: [String: Any] = [:]
        if let description {
            mapping["description"] = description
        }
        if !references.isEmpty {
            mapping["references"] = references
        }
        if let link {
            mapping["_link"] = link
        }
        return mapping
    }
}

/// Represents the complete contents of a `treedocs.yaml` state file.
///
/// The model mirrors the root YAML object: project metadata, optional configuration overrides, an
/// optional filesystem signature, and the recursive documentation tree.
struct TreedocsFile: Equatable {
    /// The treedocs file-format schema version stored at root `schema_version`.
    var schemaVersion: String

    /// Project metadata from the root `project` section.
    var project: ProjectMetadata

    /// Optional configuration overrides stored in the state file.
    var overrides: TreedocsConfig?

    /// The stored filesystem structure signature.
    var signature: String?

    /// The documented repository tree.
    var tree: [String: TreeEntry]

    /// Creates a treedocs file model.
    ///
    /// - Parameters:
    ///   - project: Project metadata for the state file.
    ///   - overrides: Optional configuration overrides stored with the state.
    ///   - signature: Optional filesystem signature.
    ///   - tree: The documented repository tree.
    init(
        schemaVersion: String = TreedocsSchemaMetadata.currentVersion,
        project: ProjectMetadata = ProjectMetadata(),
        overrides: TreedocsConfig? = nil,
        signature: String? = nil,
        tree: [String: TreeEntry] = [:]
    ) {
        self.schemaVersion = schemaVersion.trimmedNilIfEmpty ?? TreedocsSchemaMetadata.currentVersion
        self.project = project
        self.overrides = overrides
        self.signature = signature
        self.tree = tree
    }

    /// Parses a complete state file from YAML text.
    ///
    /// Empty YAML produces a default empty state. Root mappings are parsed by section, and tree keys
    /// containing slashes are inserted into nested tree dictionaries.
    ///
    /// - Parameter yaml: The raw YAML text to parse.
    /// - Returns: The parsed state file model.
    /// - Throws: `TreeDocsError` when the root or nested values have invalid shapes, plus YAML parser errors from Yams.
    static func load(from yaml: String) throws -> TreedocsFile {
        guard let raw = try Yams.load(yaml: yaml) else {
            return TreedocsFile()
        }

        guard let mapping = raw as? [String: Any] else {
            throw TreeDocsError.message("treedocs.yaml must contain a root mapping.")
        }

        let project = ProjectMetadata.fromYAML(mapping["project"]) ?? ProjectMetadata()
        let schemaVersion = parseString(mapping["schema_version"]) ?? TreedocsSchemaMetadata.currentVersion
        let overrides = try TreedocsConfig.fromYAML(mapping["overrides"])
        let signature = parseString(mapping["signature"])

        var tree: [String: TreeEntry] = [:]
        if let treeMapping = mapping["tree"] as? [String: Any] {
            for (key, value) in treeMapping {
                let entry = try TreeEntry.fromYAML(value)
                TreeOperations.insert(entry: entry, at: RelativePath.components(for: key), into: &tree)
            }
        }

        return TreedocsFile(
            schemaVersion: schemaVersion,
            project: project,
            overrides: overrides,
            signature: signature,
            tree: tree
        )
    }

    /// Serializes the state file to formatted YAML text.
    ///
    /// Empty project and override sections are omitted, tree keys are emitted in sorted order, and the
    /// output uses two-space indentation with sorted mapping keys for deterministic diffs.
    ///
    /// - Returns: A YAML string suitable for writing to `treedocs.yaml`.
    /// - Throws: YAML serialization errors from Yams.
    func toYAMLString() throws -> String {
        var root: [String: Any] = [:]
        root["schema_version"] = schemaVersion
        let projectValue = project.toYAMLValue()
        if !projectValue.isEmpty {
            root["project"] = projectValue
        }
        if let overrides {
            let value = overrides.toYAMLValue()
            if !value.isEmpty {
                root["overrides"] = value
            }
        }
        if let signature {
            root["signature"] = signature
        }

        var treeValue: [String: Any] = [:]
        for key in tree.keys.sorted() {
            treeValue[key] = tree[key]?.toYAMLValue()
        }
        root["tree"] = treeValue

        return try Yams.dump(
            object: root,
            indent: 2,
            allowUnicode: true,
            lineBreak: .ln,
            sortKeys: true
        )
    }
}
