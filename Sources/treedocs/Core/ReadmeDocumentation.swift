import Foundation
import MarkdownUtilitiesCore
import PathKit

/// Documentation fields read from one README frontmatter mapping.
struct ReadmeEntryMetadata: Equatable {
    /// The normalized non-blank description, or `nil` when the key is absent or blank.
    var description: String?

    /// Whether the mapping explicitly contains `references`, including an empty array.
    var referencesPresent: Bool

    /// De-duplicated repository-relative paths, Markdown links, and HTTPS URLs.
    var references: [String]

    /// Whether the mapping contributes any supported field.
    var isEmpty: Bool {
        description == nil && !referencesPresent
    }
}

/// Documentation contributed for one descendant named in a README `tree` mapping.
struct ReadmeDescendantMetadata: Equatable {
    /// Repository-relative path to the documented descendant.
    let targetPath: String

    /// Keys used to reach the entry inside the README's `tree` mapping.
    let frontMatterPath: [String]

    /// Whether the entry uses directory `_doc` metadata.
    let isDirectory: Bool

    /// Supported documentation fields contributed by the entry.
    let metadata: ReadmeEntryMetadata
}

/// A selected Markdown source and the folder, file, and descendant metadata it contributes.
///
/// Source-file metadata may use modern `file:` or legacy `readme:` frontmatter. The loader rejects
/// conflicting dual mappings before reconciliation; updates retain each existing key spelling.
struct ReadmeDocumentationSource {
    /// Repository-relative path to the README.
    let path: String

    /// Repository-relative path to the README's containing folder, or an empty string at the root.
    let folderPath: String

    /// Exact source snapshot used to prevent overwriting concurrent edits.
    let originalSource: String

    /// Markdown document owned and rendered by `MarkdownUtilitiesCore`.
    var document: MarkdownDocument

    /// Top-level frontmatter fields that document the containing folder.
    let folderMetadata: ReadmeEntryMetadata

    /// Fields nested under `file` or legacy `readme` that document the source file itself.
    let readmeMetadata: ReadmeEntryMetadata

    /// Sparse descendant fields nested under the optional `tree` mapping.
    let descendants: [ReadmeDescendantMetadata]

    /// Whether the README is directly inside the repository root.
    var isRoot: Bool { folderPath.isEmpty }

    /// Writes one resolved treedocs value into the corresponding frontmatter field.
    ///
    /// Repository-relative references are converted back to paths relative to the README folder.
    ///
    /// - Parameters:
    ///   - value: The resolved description or references.
    ///   - field: The supported frontmatter field to replace.
    ///   - target: Frontmatter location to update.
    /// - Throws: ``TreeDocsError`` for mismatched field/value pairs or invalid reference paths.
    /// - Note: Source-file updates keep both `file:` and `readme:` consistent when both are present.
    mutating func set(_ value: ReadmeConflictValue, field: ReadmeMetadataField, target: ReadmeMetadataTarget) throws {
        switch target {
        case .folder:
            try set(value, field: field, in: &document.frontMatter)
        case .readme:
            let keys = ["file", "readme"].filter { document.frontMatter[$0] != nil }
            for key in keys.isEmpty ? ["file"] : keys {
                var nested = document.frontMatter[key]?.mapping ?? FrontMatter()
                try set(value, field: field, in: &nested)
                document.frontMatter[key] = .object(nested)
            }
        case let .tree(frontMatterPath, isDirectory):
            var tree = document.frontMatter["tree"]?.mapping ?? FrontMatter()
            try set(
                value,
                field: field,
                at: frontMatterPath,
                isDirectory: isDirectory,
                in: &tree
            )
            document.frontMatter["tree"] = .object(tree)
        }
    }

    /// Adds missing descendant descriptions from the resolved treedocs tree.
    mutating func populate(from tree: [String: TreeEntry], depth: ReadmePopulationDepth) throws {
        let prefix = folderPath.isEmpty ? "" : folderPath + "/"
        let existingDescriptionPaths = Set(descendants.compactMap { descendant in
            descendant.metadata.description == nil ? nil : descendant.targetPath
        })

        for (path, entry) in TreeOperations.flatten(tree) {
            guard path != self.path, path.hasPrefix(prefix) else { continue }
            let relativePath = String(path.dropFirst(prefix.count))
            guard !relativePath.isEmpty else { continue }
            if depth == .children, relativePath.contains("/") { continue }
            guard !existingDescriptionPaths.contains(path), let description = entry.description?.trimmedNilIfEmpty else {
                continue
            }

            try set(
                .description(description),
                field: .description,
                target: .tree(
                    frontMatterPath: RelativePath.components(for: relativePath),
                    isDirectory: entry.isDirectory
                )
            )
        }
    }

    /// Renders the document through `MarkdownUtilitiesCore`, preserving its body and unsupported metadata semantically.
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

    private func set(
        _ value: ReadmeConflictValue,
        field: ReadmeMetadataField,
        at path: [String],
        isDirectory: Bool,
        in mapping: inout FrontMatter
    ) throws {
        guard let key = path.first else {
            throw TreeDocsError.message("Internal README tree path mismatch for \(self.path).")
        }

        if path.count == 1 {
            if isDirectory {
                var directory = mapping[key]?.mapping ?? FrontMatter()
                directory["_doc"] = try updatedMetadataValue(
                    directory["_doc"],
                    value: value,
                    field: field
                )
                mapping[key] = .object(directory)
            } else {
                mapping[key] = try updatedMetadataValue(mapping[key], value: value, field: field)
            }
            return
        }

        var child = mapping[key]?.mapping ?? FrontMatter()
        try set(value, field: field, at: Array(path.dropFirst()), isDirectory: isDirectory, in: &child)
        mapping[key] = .object(child)
    }

    private func updatedMetadataValue(
        _ existing: FrontMatterValue?,
        value: ReadmeConflictValue,
        field: ReadmeMetadataField
    ) throws -> FrontMatterValue {
        if case let .description(description) = value,
           field == .description,
           existing?.mapping == nil {
            return .string(description)
        }

        var mapping = existing?.mapping ?? FrontMatter()
        if let existingDescription = existing?.stringValue {
            mapping["description"] = .string(existingDescription)
        }
        try set(value, field: field, in: &mapping)
        return .object(mapping)
    }
}

/// Loads supported YAML frontmatter from documentation sources selected by ``TreeScanner``.
struct ReadmeDocumentationLoader {
    /// Reads and adapts recognized README files beneath a repository root.
    ///
    /// - Parameters:
    ///   - root: Repository root used to resolve scanner-produced paths.
    ///   - readmePaths: Selected documentation source paths discovered by ``TreeScanner``.
    /// - Returns: Sources containing a supported folder, README-file, or descendant-tree field.
    /// - Throws: Read failures, `MarkdownUtilitiesCore` parsing failures, or supported-field validation errors.
    func load(root: Path, readmePaths: [String]) throws -> [ReadmeDocumentationSource] {
        try readmePaths.compactMap { relativePath in
            let absolutePath = root + Path(relativePath)
            let source: String = try absolutePath.read()
            return try parse(source: source, relativePath: relativePath)
        }
    }

    /// Adapts a selected source using `MarkdownUtilitiesCore` for Markdown and frontmatter parsing.
    ///
    /// Modern `file:` and legacy `readme:` mappings describe the source itself, independently of its
    /// filename or the state schema version. Dual mappings must agree on supported metadata after
    /// normalization, including references compared as sets.
    ///
    /// - Parameters:
    ///   - source: Complete README source text.
    ///   - relativePath: Repository-relative path used for diagnostics and reference resolution.
    /// - Returns: A documentation source, or `nil` when YAML frontmatter has no supported metadata.
    /// - Throws: ``TreeDocsError`` when YAML frontmatter is malformed, a supported field has the
    ///   wrong type, or `file:` and `readme:` disagree.
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

        if let fileValue = document.frontMatter["file"], let legacy = document.frontMatter["readme"] {
            guard let fileMapping = fileValue.mapping, let legacyMapping = legacy.mapping else {
                throw TreeDocsError.message("Invalid YAML frontmatter in \(relativePath): file and readme must be mappings.")
            }
            let modern = try metadata(from: fileMapping, label: "\(relativePath) file", folderPath: folderPath)
            let old = try metadata(from: legacyMapping, label: "\(relativePath) readme", folderPath: folderPath)
            guard modern.description == old.description,
                  modern.referencesPresent == old.referencesPresent,
                  Set(modern.references) == Set(old.references) else {
                throw TreeDocsError.message("Conflicting file and readme metadata in \(relativePath). Combine the metadata under file before retrying.")
            }
        }
        let readmeMetadata: ReadmeEntryMetadata
        if let readmeValue = document.frontMatter["file"] ?? document.frontMatter["readme"] {
            guard let readmeMapping = readmeValue.mapping else {
                throw TreeDocsError.message("Invalid YAML frontmatter in \(relativePath): file/readme must be a mapping.")
            }
            readmeMetadata = try metadata(from: readmeMapping, label: "\(relativePath) readme", folderPath: folderPath)
        } else {
            readmeMetadata = ReadmeEntryMetadata(description: nil, referencesPresent: false, references: [])
        }

        let treePresent = document.frontMatter["tree"] != nil
        let descendants: [ReadmeDescendantMetadata]
        if let treeValue = document.frontMatter["tree"] {
            guard let treeMapping = treeValue.mapping else {
                throw TreeDocsError.message("Invalid YAML frontmatter in \(relativePath): tree must be a mapping.")
            }
            descendants = try descendantMetadata(
                from: treeMapping,
                readmePath: relativePath,
                folderPath: folderPath
            )
        } else {
            descendants = []
        }

        guard !folderMetadata.isEmpty || !readmeMetadata.isEmpty || treePresent else {
            return nil
        }

        return ReadmeDocumentationSource(
            path: relativePath,
            folderPath: folderPath,
            originalSource: source,
            document: document,
            folderMetadata: folderMetadata,
            readmeMetadata: readmeMetadata,
            descendants: descendants
        )
    }

    private func descendantMetadata(
        from tree: FrontMatter,
        readmePath: String,
        folderPath: String
    ) throws -> [ReadmeDescendantMetadata] {
        var result: [ReadmeDescendantMetadata] = []
        for (key, value) in tree {
            let components = try descendantComponents(for: key, readmePath: readmePath)
            try appendDescendantMetadata(
                value: value,
                canonicalComponents: components,
                frontMatterPath: [key],
                readmePath: readmePath,
                folderPath: folderPath,
                result: &result
            )
        }
        var seenPaths = Set<String>()
        for descendant in result where !seenPaths.insert(descendant.targetPath).inserted {
            throw TreeDocsError.message(
                "Invalid YAML frontmatter in \(readmePath): duplicate tree path \(descendant.targetPath)."
            )
        }
        return result
    }

    private func appendDescendantMetadata(
        value: FrontMatterValue,
        canonicalComponents: [String],
        frontMatterPath: [String],
        readmePath: String,
        folderPath: String,
        result: inout [ReadmeDescendantMetadata]
    ) throws {
        let targetPath = (RelativePath.components(for: folderPath) + canonicalComponents).joined(separator: "/")
        let label = "\(readmePath) tree.\(frontMatterPath.joined(separator: "."))"

        if let description = value.stringValue {
            let metadata = ReadmeEntryMetadata(
                description: description.trimmedNilIfEmpty,
                referencesPresent: false,
                references: []
            )
            if !metadata.isEmpty {
                result.append(ReadmeDescendantMetadata(
                    targetPath: targetPath,
                    frontMatterPath: frontMatterPath,
                    isDirectory: false,
                    metadata: metadata
                ))
            }
            return
        }

        guard let mapping = value.mapping else {
            throw TreeDocsError.message("Invalid YAML frontmatter in \(label): tree entries must be strings or mappings.")
        }

        let reservedKeys = Set(["description", "references", "_doc", "_link"])
        let childKeys = mapping.keys.filter { !reservedKeys.contains($0) }
        let isDirectory = mapping["_doc"] != nil || !childKeys.isEmpty

        if isDirectory {
            if mapping["description"] != nil || mapping["references"] != nil {
                throw TreeDocsError.message("Invalid YAML frontmatter in \(label): directory metadata must be nested under _doc.")
            }
            if let docValue = mapping["_doc"] {
                let metadata = try metadata(from: docValue, label: "\(label)._doc", folderPath: folderPath)
                if !metadata.isEmpty {
                    result.append(ReadmeDescendantMetadata(
                        targetPath: targetPath,
                        frontMatterPath: frontMatterPath,
                        isDirectory: true,
                        metadata: metadata
                    ))
                }
            }

            for childKey in childKeys {
                guard let childValue = mapping[childKey] else { continue }
                let childComponents = try descendantComponents(for: childKey, readmePath: readmePath)
                try appendDescendantMetadata(
                    value: childValue,
                    canonicalComponents: canonicalComponents + childComponents,
                    frontMatterPath: frontMatterPath + [childKey],
                    readmePath: readmePath,
                    folderPath: folderPath,
                    result: &result
                )
            }
        } else {
            let metadata = try metadata(from: mapping, label: label, folderPath: folderPath)
            if !metadata.isEmpty {
                result.append(ReadmeDescendantMetadata(
                    targetPath: targetPath,
                    frontMatterPath: frontMatterPath,
                    isDirectory: false,
                    metadata: metadata
                ))
            }
        }
    }

    private func descendantComponents(for key: String, readmePath: String) throws -> [String] {
        let normalized = key.replacingOccurrences(of: "\\", with: "/")
        let rawComponents = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !normalized.hasPrefix("/"),
              !rawComponents.isEmpty,
              rawComponents.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0 != "_doc" }) else {
            throw TreeDocsError.message("Invalid YAML frontmatter in \(readmePath): tree path escapes the README subtree: \(key)")
        }
        return rawComponents
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

    private func metadata(from value: FrontMatterValue, label: String, folderPath: String) throws -> ReadmeEntryMetadata {
        if let description = value.stringValue {
            return ReadmeEntryMetadata(
                description: description.trimmedNilIfEmpty,
                referencesPresent: false,
                references: []
            )
        }
        guard let mapping = value.mapping else {
            throw TreeDocsError.message("Invalid YAML frontmatter in \(label): metadata must be a string or mapping.")
        }
        return try metadata(from: mapping, label: label, folderPath: folderPath)
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

/// Normalizes references between README-relative and repository-relative forms.
enum ReadmeReferenceNormalizer {
    /// Converts a README reference into the canonical form stored in `treedocs.yaml`.
    ///
    /// HTTPS URLs are unchanged. Local destinations, including destinations inside Markdown links,
    /// are resolved from `folderPath` and rejected if they escape the repository.
    ///
    /// - Parameters:
    ///   - reference: README-relative local path, Markdown link, or HTTPS URL.
    ///   - folderPath: Repository-relative path to the README's containing folder.
    /// - Returns: A repository-relative reference or the unchanged HTTPS reference.
    /// - Throws: `TreeDocsError` for escaping paths, unsupported URL schemes, or empty local targets.
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

    /// Converts a canonical treedocs reference back to README-relative form.
    ///
    /// - Parameters:
    ///   - reference: Repository-relative local path, Markdown link, or HTTPS URL.
    ///   - folderPath: Repository-relative path to the README's containing folder.
    /// - Returns: A README-relative reference or the unchanged HTTPS reference.
    /// - Throws: `TreeDocsError` when the reference uses an unsupported URL scheme.
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

/// Requested scope when copying canonical descriptions into recognized READMEs.
enum ReadmePopulationDepth: String, Equatable {
    /// Populate only immediate children of each README's containing directory.
    case children

    /// Populate every owned descendant beneath each README's containing directory.
    case recursive
}

/// The frontmatter location documented by a supported README mapping.
enum ReadmeMetadataTarget: Equatable {
    /// Top-level fields documenting the README's containing folder.
    case folder

    /// Nested `readme` fields documenting the README file.
    case readme

    /// An entry inside the optional sparse descendant tree.
    case tree(frontMatterPath: [String], isDirectory: Bool)
}

/// Supported field names reconciled independently between README and treedocs state.
enum ReadmeMetadataField: String, Equatable, Hashable {
    /// Human-readable path documentation.
    case description

    /// Related repository paths, Markdown links, or HTTPS URLs.
    case references
}

/// A typed README or treedocs field value shown during conflict resolution.
enum ReadmeConflictValue: Equatable, CustomStringConvertible {
    /// One non-blank description.
    case description(String)

    /// A de-duplicated reference collection compared without regard to order.
    case references([String])

    /// Compact text used in conflict diagnostics and prompts.
    var description: String {
        switch self {
        case let .description(value): value
        case let .references(values): values.isEmpty ? "[]" : values.joined(separator: ", ")
        }
    }
}

/// One README source participating in a grouped metadata conflict.
struct ReadmeConflictSourceValue: Equatable {
    /// README containing the competing value.
    let readmePath: String

    /// Location to update if another value wins.
    let target: ReadmeMetadataTarget

    /// Normalized value contributed by this README.
    let value: ReadmeConflictValue
}

/// One path/field disagreement across treedocs and any number of READMEs.
struct ReadmeMetadataConflict: Equatable {
    /// Stable path/field identifier used to associate an interactive decision.
    let id: String

    /// Repository-relative tree path whose metadata is in conflict.
    let targetPath: String

    /// Supported metadata field that differs.
    let field: ReadmeMetadataField

    /// Values and mutation locations contributed by participating READMEs.
    let readmeValues: [ReadmeConflictSourceValue]

    /// Value loaded from `treedocs.yaml`, or `nil` when only READMEs disagree.
    let treedocsValue: ReadmeConflictValue?

    /// Distinct normalized values available for interactive selection.
    var values: [ReadmeConflictValue] {
        var result: [ReadmeConflictValue] = []
        for value in [treedocsValue].compactMap({ $0 }) + readmeValues.map(\.value) where !result.contains(value) {
            result.append(value)
        }
        return result
    }

    /// Human-readable path, field, and competing values for non-interactive output.
    var diagnostic: String {
        var sources = readmeValues.map { "\($0.readmePath): \($0.value)" }
        if let treedocsValue {
            sources.append("treedocs.yaml: \(treedocsValue)")
        }
        return "\(targetPath) [\(field.rawValue)] — " + sources.joined(separator: "; ")
    }
}

/// Source selected as authoritative for one metadata conflict.
enum ReadmeConflictWinner: Equatable {
    /// Apply the selected normalized value to treedocs and all participating READMEs.
    case value(ReadmeConflictValue)
}

/// Staged README imports, conflicts, warnings, and potential file updates.
struct ReadmeReconciliation {
    /// Candidate tree after applying non-conflicting README imports and defaults.
    var tree: [String: TreeEntry]

    /// Parsed README sources, including any staged frontmatter changes.
    var sources: [ReadmeDocumentationSource]

    /// Field differences that require an explicit winner before writing.
    var conflicts: [ReadmeMetadataConflict]

    /// Human-readable fields that would be imported into `treedocs.yaml`.
    var pendingImports: [String]

    /// Non-failing limitations, such as deferred root-folder metadata.
    var warnings: [String]

    /// Applies one winner for every conflict to the staged tree or README documents.
    ///
    /// - Parameter resolutions: Winners keyed by ``ReadmeMetadataConflict/id``.
    /// - Throws: `TreeDocsError` when a resolution is missing or its README source is unavailable.
    mutating func apply(resolutions: [String: ReadmeConflictWinner]) throws {
        for conflict in conflicts {
            guard let winner = resolutions[conflict.id] else {
                throw TreeDocsError.message("Missing resolution for README conflict \(conflict.id).")
            }
            let value: ReadmeConflictValue
            switch winner {
            case let .value(selected):
                guard conflict.values.contains(selected) else {
                    throw TreeDocsError.message("Invalid resolution for README conflict \(conflict.id).")
                }
                value = selected
            }

            applyToTree(value, targetPath: conflict.targetPath, field: conflict.field)
            for sourceValue in conflict.readmeValues {
                guard let index = sources.firstIndex(where: { $0.path == sourceValue.readmePath }) else {
                    throw TreeDocsError.message("README source disappeared during reconciliation: \(sourceValue.readmePath)")
                }
                try sources[index].set(value, field: conflict.field, target: sourceValue.target)
            }
        }
    }

    /// Copies missing canonical descriptions into recognized README trees.
    mutating func populateReadmes(from resolvedTree: [String: TreeEntry], depth: ReadmePopulationDepth) throws {
        for index in sources.indices {
            try sources[index].populate(from: resolvedTree, depth: depth)
        }
    }

    private mutating func applyToTree(
        _ value: ReadmeConflictValue,
        targetPath: String,
        field: ReadmeMetadataField
    ) {
        TreeOperations.updateEntry(at: targetPath, in: &tree) { entry in
            var documentation = entry.documentation ?? EntryDocumentation()
            switch (field, value) {
            case let (.description, .description(description)):
                documentation.description = description
            case let (.references, .references(references)):
                documentation.references = references
            default:
                break
            }
            entry.documentation = documentation
        }
    }
}

/// Compares README metadata with the corresponding entries in a treedocs tree.
struct ReadmeReconciler {
    private struct FieldKey: Hashable {
        let targetPath: String
        let field: ReadmeMetadataField
    }

    private struct Contribution {
        let sourcePath: String
        let target: ReadmeMetadataTarget
        let value: ReadmeConflictValue
    }

    /// Stages non-conflicting imports, deterministic README defaults, and field conflicts.
    ///
    /// This method performs no filesystem writes. Reference arrays are compared as order-insensitive sets.
    ///
    /// - Parameters:
    ///   - sources: Recognized README documents and their supported metadata.
    ///   - tree: Scanned tree with existing treedocs metadata already merged.
    /// - Returns: A staged reconciliation ready for conflict decisions and transactional writing.
    func reconcile(sources: [ReadmeDocumentationSource], tree: [String: TreeEntry]) -> ReadmeReconciliation {
        var result = ReadmeReconciliation(tree: tree, sources: sources, conflicts: [], pendingImports: [], warnings: [])
        var contributions: [FieldKey: [Contribution]] = [:]

        for source in sources {
            if source.isRoot, !source.folderMetadata.isEmpty {
                result.warnings.append("\(source.path): root-folder README metadata is deferred; readme.* and tree metadata are still used.")
            } else {
                collect(
                    metadata: source.folderMetadata,
                    targetPath: source.folderPath,
                    target: .folder,
                    source: source,
                    contributions: &contributions
                )
            }

            collect(
                metadata: source.readmeMetadata,
                targetPath: source.path,
                target: .readme,
                source: source,
                contributions: &contributions
            )

            for descendant in source.descendants {
                guard let scannedEntry = TreeOperations.entry(at: descendant.targetPath, in: tree),
                      scannedEntry.isDirectory == descendant.isDirectory else {
                    result.warnings.append(
                        "\(source.path): tree entry \(descendant.targetPath) is missing, has a different type, or is outside the owned scanned subtree and was ignored."
                    )
                    continue
                }
                collect(
                    metadata: descendant.metadata,
                    targetPath: descendant.targetPath,
                    target: .tree(
                        frontMatterPath: descendant.frontMatterPath,
                        isDirectory: descendant.isDirectory
                    ),
                    source: source,
                    contributions: &contributions
                )
            }
        }

        for key in contributions.keys.sorted(by: {
            ($0.targetPath, $0.field.rawValue) < ($1.targetPath, $1.field.rawValue)
        }) {
            guard let values = contributions[key], let entry = TreeOperations.entry(at: key.targetPath, in: result.tree) else {
                continue
            }
            let treedocsValue = value(for: key.field, entry: entry)
            let distinctReadmeValues = unique(values.map(\.value))
            let allValues = unique([treedocsValue].compactMap { $0 } + distinctReadmeValues)

            if treedocsValue == nil, allValues.count == 1, let imported = allValues.first {
                if imported != .references([]) {
                    apply(imported, field: key.field, targetPath: key.targetPath, tree: &result.tree)
                    result.pendingImports.append("\(key.targetPath) [\(key.field.rawValue)]")
                }
            } else if allValues.count > 1 {
                result.conflicts.append(ReadmeMetadataConflict(
                    id: "\(key.targetPath)|\(key.field.rawValue)",
                    targetPath: key.targetPath,
                    field: key.field,
                    readmeValues: values.map {
                        ReadmeConflictSourceValue(
                            readmePath: $0.sourcePath,
                            target: $0.target,
                            value: $0.value
                        )
                    },
                    treedocsValue: treedocsValue
                ))
            }
        }

        for source in sources {
            let hasDescriptionConflict = result.conflicts.contains {
                $0.targetPath == source.path && $0.field == .description
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

    private func collect(
        metadata: ReadmeEntryMetadata,
        targetPath: String,
        target: ReadmeMetadataTarget,
        source: ReadmeDocumentationSource,
        contributions: inout [FieldKey: [Contribution]]
    ) {
        if let description = metadata.description {
            contributions[FieldKey(targetPath: targetPath, field: .description), default: []].append(
                Contribution(sourcePath: source.path, target: target, value: .description(description))
            )
        }

        if metadata.referencesPresent {
            contributions[FieldKey(targetPath: targetPath, field: .references), default: []].append(
                Contribution(sourcePath: source.path, target: target, value: .references(metadata.references.sorted()))
            )
        }
    }

    private func value(for field: ReadmeMetadataField, entry: TreeEntry) -> ReadmeConflictValue? {
        switch field {
        case .description:
            return entry.description?.trimmedNilIfEmpty.map(ReadmeConflictValue.description)
        case .references:
            return entry.references.isEmpty ? nil : .references(entry.references.sorted())
        }
    }

    private func unique(_ values: [ReadmeConflictValue]) -> [ReadmeConflictValue] {
        var result: [ReadmeConflictValue] = []
        for value in values where !result.contains(value) {
            result.append(value)
        }
        return result
    }

    private func apply(
        _ value: ReadmeConflictValue,
        field: ReadmeMetadataField,
        targetPath: String,
        tree: inout [String: TreeEntry]
    ) {
        TreeOperations.updateEntry(at: targetPath, in: &tree) { entry in
            var documentation = entry.documentation ?? EntryDocumentation()
            switch (field, value) {
            case let (.description, .description(description)):
                documentation.description = description
            case let (.references, .references(references)):
                documentation.references = references
            default:
                break
            }
            entry.documentation = documentation
        }
    }
}
