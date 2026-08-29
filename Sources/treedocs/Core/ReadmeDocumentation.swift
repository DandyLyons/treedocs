import Foundation
import MarkdownUtilitiesCore
import PathKit

/// Documentation fields read from one README frontmatter mapping.
struct ReadmeEntryMetadata: Equatable {
    var description: String?
    var referencesPresent: Bool
    var references: [String]

    var isEmpty: Bool {
        description == nil && !referencesPresent
    }
}

/// A parsed README and the documentation metadata it contributes.
struct ReadmeDocumentationSource {
    let path: String
    let folderPath: String
    let originalSource: String
    var document: MarkdownDocument
    let folderMetadata: ReadmeEntryMetadata
    let readmeMetadata: ReadmeEntryMetadata

    var isRoot: Bool { folderPath.isEmpty }

    mutating func set(_ value: ReadmeConflictValue, field: ReadmeMetadataField, target: ReadmeMetadataTarget) throws {
        switch target {
        case .folder:
            try set(value, field: field, in: &document.frontMatter)
        case .readme:
            var nested = document.frontMatter["readme"]?.mapping ?? FrontMatter()
            try set(value, field: field, in: &nested)
            document.frontMatter["readme"] = .object(nested)
        }
    }

    func renderedSource() throws -> String {
        try document.render()
    }

    private func set(_ value: ReadmeConflictValue, field: ReadmeMetadataField, in mapping: inout FrontMatter) throws {
        switch (field, value) {
        case let (.description, .description(description)):
            mapping["description"] = .string(description)
        case let (.references, .references(references)):
            let relative = try references.map { try ReadmeReferenceNormalizer.readmeReference($0, folderPath: folderPath) }
            mapping["references"] = .array(relative.map(FrontMatterValue.string))
        default:
            throw TreeDocsError.message("Internal README reconciliation field mismatch for \(path).")
        }
    }
}

/// Loads supported YAML frontmatter from scanner-discovered README files.
struct ReadmeDocumentationLoader {
    func load(root: Path, readmePaths: [String]) throws -> [ReadmeDocumentationSource] {
        try readmePaths.compactMap { relativePath in
            let absolutePath = root + Path(relativePath)
            let source: String = try absolutePath.read()
            return try parse(source: source, relativePath: relativePath)
        }
    }

    func parse(source: String, relativePath: String) throws -> ReadmeDocumentationSource? {
        guard source.hasPrefix("---\n") else {
            return nil
        }

        let document: MarkdownDocument
        do {
            document = try MarkdownDocument(content: source)
        } catch {
            throw TreeDocsError.message("Invalid YAML frontmatter in \(relativePath): \(error.localizedDescription)")
        }

        guard document.frontMatterFormat == .yaml else {
            throw TreeDocsError.message("Invalid YAML frontmatter in \(relativePath): missing closing --- delimiter.")
        }

        let folderPath = RelativePath.components(for: relativePath).dropLast().joined(separator: "/")
        let folderMetadata = try metadata(from: document.frontMatter, label: relativePath, folderPath: folderPath)

        let readmeMetadata: ReadmeEntryMetadata
        if let readmeValue = document.frontMatter["readme"] {
            guard let readmeMapping = readmeValue.mapping else {
                throw TreeDocsError.message("Invalid YAML frontmatter in \(relativePath): readme must be a mapping.")
            }
            readmeMetadata = try metadata(from: readmeMapping, label: "\(relativePath) readme", folderPath: folderPath)
        } else {
            readmeMetadata = ReadmeEntryMetadata(description: nil, referencesPresent: false, references: [])
        }

        guard !folderMetadata.isEmpty || !readmeMetadata.isEmpty else {
            return nil
        }

        return ReadmeDocumentationSource(
            path: relativePath,
            folderPath: folderPath,
            originalSource: source,
            document: document,
            folderMetadata: folderMetadata,
            readmeMetadata: readmeMetadata
        )
    }

    private func metadata(from mapping: FrontMatter, label: String, folderPath: String) throws -> ReadmeEntryMetadata {
        let description: String?
        if let value = mapping["description"] {
            guard let string = value.stringValue else {
                throw TreeDocsError.message("Invalid YAML frontmatter in \(label): description must be a string.")
            }
            description = string.trimmedNilIfEmpty
        } else {
            description = nil
        }

        let referencesPresent = mapping["references"] != nil
        var references: [String] = []
        if let value = mapping["references"] {
            guard let sequence = value.sequence else {
                throw TreeDocsError.message("Invalid YAML frontmatter in \(label): references must be an array of strings.")
            }
            for item in sequence {
                guard let reference = item.stringValue?.trimmedNilIfEmpty else {
                    throw TreeDocsError.message("Invalid YAML frontmatter in \(label): references must be an array of non-empty strings.")
                }
                references.append(try ReadmeReferenceNormalizer.canonicalReference(reference, folderPath: folderPath))
            }
            references = Self.unique(references)
        }

        return ReadmeEntryMetadata(
            description: description,
            referencesPresent: referencesPresent,
            references: references
        )
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

/// Normalizes references between README-relative and repository-relative forms.
enum ReadmeReferenceNormalizer {
    static func canonicalReference(_ reference: String, folderPath: String) throws -> String {
        try transform(reference) { target in
            guard !target.hasPrefix("/") else {
                throw TreeDocsError.message("README reference must be repository-relative: \(reference)")
            }
            let base = RelativePath.components(for: folderPath)
            var result = base
            for component in target.replacingOccurrences(of: "\\", with: "/").split(separator: "/").map(String.init) {
                switch component {
                case "", ".":
                    continue
                case "..":
                    guard !result.isEmpty else {
                        throw TreeDocsError.message("README reference escapes the repository: \(reference)")
                    }
                    result.removeLast()
                default:
                    result.append(component)
                }
            }
            guard !result.isEmpty else {
                throw TreeDocsError.message("README reference must identify a repository path: \(reference)")
            }
            return result.joined(separator: "/")
        }
    }

    static func readmeReference(_ reference: String, folderPath: String) throws -> String {
        try transform(reference) { target in
            let base = RelativePath.components(for: folderPath)
            let destination = RelativePath.components(for: target)
            var commonCount = 0
            while commonCount < base.count, commonCount < destination.count, base[commonCount] == destination[commonCount] {
                commonCount += 1
            }
            return Array(repeating: "..", count: base.count - commonCount)
                .appending(contentsOf: destination.dropFirst(commonCount))
                .joined(separator: "/")
        }
    }

    private static func transform(_ reference: String, localTransform: (String) throws -> String) throws -> String {
        if reference.hasPrefix("https://") {
            return reference
        }
        if let link = markdownLink(reference) {
            if link.target.hasPrefix("https://") {
                return reference
            }
            return "[\(link.label)](\(try localTransform(link.target)))"
        }
        if reference.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil {
            throw TreeDocsError.message("Unsupported README reference URL: \(reference)")
        }
        return try localTransform(reference)
    }

    private static func markdownLink(_ value: String) -> (label: String, target: String)? {
        guard value.hasPrefix("["), value.hasSuffix(")"), let divider = value.range(of: "](") else {
            return nil
        }
        let label = String(value[value.index(after: value.startIndex)..<divider.lowerBound])
        let target = String(value[divider.upperBound..<value.index(before: value.endIndex)])
        guard !label.isEmpty, !target.isEmpty else { return nil }
        return (label, target)
    }
}

private extension Array where Element == String {
    func appending<S: Sequence>(contentsOf values: S) -> [String] where S.Element == String {
        self + Array(values)
    }
}

enum ReadmeMetadataTarget: String, Equatable {
    case folder
    case readme
}

enum ReadmeMetadataField: String, Equatable {
    case description
    case references
}

enum ReadmeConflictValue: Equatable, CustomStringConvertible {
    case description(String)
    case references([String])

    var description: String {
        switch self {
        case let .description(value): value
        case let .references(values): values.isEmpty ? "[]" : values.joined(separator: ", ")
        }
    }
}

struct ReadmeMetadataConflict: Equatable {
    let id: String
    let readmePath: String
    let targetPath: String
    let target: ReadmeMetadataTarget
    let field: ReadmeMetadataField
    let readmeValue: ReadmeConflictValue
    let treedocsValue: ReadmeConflictValue

    var diagnostic: String {
        "\(targetPath) [\(field.rawValue)] — README: \(readmeValue); treedocs: \(treedocsValue)"
    }
}

enum ReadmeConflictWinner: Equatable {
    case readme
    case treedocs
}

struct ReadmeReconciliation {
    var tree: [String: TreeEntry]
    var sources: [ReadmeDocumentationSource]
    var conflicts: [ReadmeMetadataConflict]
    var pendingImports: [String]
    var warnings: [String]

    mutating func apply(resolutions: [String: ReadmeConflictWinner]) throws {
        for conflict in conflicts {
            guard let winner = resolutions[conflict.id] else {
                throw TreeDocsError.message("Missing resolution for README conflict \(conflict.id).")
            }
            switch winner {
            case .readme:
                applyToTree(conflict.readmeValue, conflict: conflict)
            case .treedocs:
                guard let index = sources.firstIndex(where: { $0.path == conflict.readmePath }) else {
                    throw TreeDocsError.message("README source disappeared during reconciliation: \(conflict.readmePath)")
                }
                try sources[index].set(conflict.treedocsValue, field: conflict.field, target: conflict.target)
            }
        }
    }

    private mutating func applyToTree(_ value: ReadmeConflictValue, conflict: ReadmeMetadataConflict) {
        TreeOperations.updateEntry(at: conflict.targetPath, in: &tree) { entry in
            var documentation = entry.documentation ?? EntryDocumentation()
            switch value {
            case let .description(description):
                documentation.description = description
            case let .references(references):
                documentation.references = references
            }
            entry.documentation = documentation
        }
    }
}

/// Compares README metadata with the corresponding entries in a treedocs tree.
struct ReadmeReconciler {
    func reconcile(sources: [ReadmeDocumentationSource], tree: [String: TreeEntry]) -> ReadmeReconciliation {
        var result = ReadmeReconciliation(tree: tree, sources: sources, conflicts: [], pendingImports: [], warnings: [])

        for source in sources {
            if source.isRoot, !source.folderMetadata.isEmpty {
                result.warnings.append("\(source.path): root-folder README metadata is deferred; only readme.* metadata is used.")
            } else {
                reconcile(
                    metadata: source.folderMetadata,
                    targetPath: source.folderPath,
                    target: .folder,
                    source: source,
                    result: &result
                )
            }

            reconcile(
                metadata: source.readmeMetadata,
                targetPath: source.path,
                target: .readme,
                source: source,
                result: &result
            )

            let hasDescriptionConflict = result.conflicts.contains {
                $0.readmePath == source.path && $0.target == .readme && $0.field == .description
            }
            if source.readmeMetadata.description == nil,
               !hasDescriptionConflict,
               TreeOperations.entry(at: source.path, in: result.tree)?.description?.trimmedNilIfEmpty == nil {
                let defaultDescription = source.isRoot
                    ? "Project overview and documentation."
                    : "Overview and documentation for \(source.folderPath)/."
                TreeOperations.updateEntry(at: source.path, in: &result.tree) { entry in
                    var documentation = entry.documentation ?? EntryDocumentation()
                    documentation.description = defaultDescription
                    entry.documentation = documentation
                }
                result.pendingImports.append("\(source.path) [default description]")
            }
        }

        return result
    }

    private func reconcile(
        metadata: ReadmeEntryMetadata,
        targetPath: String,
        target: ReadmeMetadataTarget,
        source: ReadmeDocumentationSource,
        result: inout ReadmeReconciliation
    ) {
        guard let existing = TreeOperations.entry(at: targetPath, in: result.tree) else { return }

        if let readmeDescription = metadata.description {
            if let treedocsDescription = existing.description?.trimmedNilIfEmpty {
                if readmeDescription != treedocsDescription {
                    result.conflicts.append(conflict(
                        source: source,
                        targetPath: targetPath,
                        target: target,
                        field: .description,
                        readmeValue: .description(readmeDescription),
                        treedocsValue: .description(treedocsDescription)
                    ))
                }
            } else {
                TreeOperations.updateEntry(at: targetPath, in: &result.tree) { entry in
                    var documentation = entry.documentation ?? EntryDocumentation()
                    documentation.description = readmeDescription
                    entry.documentation = documentation
                }
                result.pendingImports.append("\(targetPath) [description]")
            }
        }

        if metadata.referencesPresent {
            let existingReferences = existing.references
            if existingReferences.isEmpty {
                if !metadata.references.isEmpty {
                    TreeOperations.updateEntry(at: targetPath, in: &result.tree) { entry in
                        var documentation = entry.documentation ?? EntryDocumentation()
                        documentation.references = metadata.references
                        entry.documentation = documentation
                    }
                    result.pendingImports.append("\(targetPath) [references]")
                }
            } else if Set(metadata.references) != Set(existingReferences) {
                result.conflicts.append(conflict(
                    source: source,
                    targetPath: targetPath,
                    target: target,
                    field: .references,
                    readmeValue: .references(metadata.references),
                    treedocsValue: .references(existingReferences)
                ))
            }
        }
    }

    private func conflict(
        source: ReadmeDocumentationSource,
        targetPath: String,
        target: ReadmeMetadataTarget,
        field: ReadmeMetadataField,
        readmeValue: ReadmeConflictValue,
        treedocsValue: ReadmeConflictValue
    ) -> ReadmeMetadataConflict {
        ReadmeMetadataConflict(
            id: "\(source.path)|\(target.rawValue)|\(field.rawValue)",
            readmePath: source.path,
            targetPath: targetPath,
            target: target,
            field: field,
            readmeValue: readmeValue,
            treedocsValue: treedocsValue
        )
    }
}
