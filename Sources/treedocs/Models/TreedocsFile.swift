import Foundation
import Yams

struct ProjectMetadata: Equatable {
    var name: String?
    var version: String?
    var lastUpdated: String?
    var extra: [String: String]

    init(name: String? = nil, version: String? = nil, lastUpdated: String? = nil, extra: [String: String] = [:]) {
        self.name = name?.trimmedNilIfEmpty
        self.version = version?.trimmedNilIfEmpty
        self.lastUpdated = lastUpdated?.trimmedNilIfEmpty
        self.extra = extra
    }

    var isEmpty: Bool {
        name == nil && version == nil && lastUpdated == nil && extra.isEmpty
    }

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

struct EntryDocumentation: Equatable {
    var description: String?
    var references: [String]

    init(description: String? = nil, references: [String] = []) {
        self.description = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.references = references
    }

    var isEmpty: Bool {
        description == nil && references.isEmpty
    }

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

struct TreeEntry: Equatable {
    var documentation: EntryDocumentation?
    var link: String?
    var children: [String: TreeEntry]
    var isDirectory: Bool

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

    init(description: String?, references: [String] = [], link: String? = nil, children: [String: TreeEntry] = [:], isDirectory: Bool = false) {
        self.init(
            documentation: EntryDocumentation(description: description, references: references),
            link: link,
            children: children,
            isDirectory: isDirectory
        )
    }

    var description: String? {
        documentation?.description
    }

    var references: [String] {
        documentation?.references ?? []
    }

    var hasReferences: Bool {
        !references.isEmpty
    }

    var needsDescription: Bool {
        (description?.isEmpty ?? true) && link == nil
    }

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

struct TreedocsFile: Equatable {
    var project: ProjectMetadata
    var overrides: TreedocsConfig?
    var signature: String?
    var tree: [String: TreeEntry]

    init(
        project: ProjectMetadata = ProjectMetadata(),
        overrides: TreedocsConfig? = nil,
        signature: String? = nil,
        tree: [String: TreeEntry] = [:]
    ) {
        self.project = project
        self.overrides = overrides
        self.signature = signature
        self.tree = tree
    }

    static func load(from yaml: String) throws -> TreedocsFile {
        guard let raw = try Yams.load(yaml: yaml) else {
            return TreedocsFile()
        }

        guard let mapping = raw as? [String: Any] else {
            throw TreeDocsError.message("treedocs.yaml must contain a root mapping.")
        }

        let project = ProjectMetadata.fromYAML(mapping["project"]) ?? ProjectMetadata()
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
            project: project,
            overrides: overrides,
            signature: signature,
            tree: tree
        )
    }

    func toYAMLString() throws -> String {
        var root: [String: Any] = [:]
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
