import Foundation
import PathKit

struct CheckReport {
    var storedSignature: String?
    var currentSignature: String
    var missingDescriptions: [String]
    var severity: CheckSeverity

    var hasSignatureDrift: Bool {
        storedSignature != currentSignature
    }

    var hasIssues: Bool {
        hasSignatureDrift || !missingDescriptions.isEmpty
    }

    var shouldFail: Bool {
        hasIssues && severity == .error
    }
}

struct InspectReport {
    var path: String
    var entry: TreeEntry
    var linkResolution: LinkResolution
    var recursiveOutput: String?
}

struct TreedocsService {
    var store = TreedocsFileStore()
    var configLoader = ConfigLoader()
    var scanner = TreeScanner()
    var renderer = TreeRenderer()
    var linkResolver = LinkResolver()

    func initialize(at rootPath: String, force: Bool) throws -> TreedocsFile {
        let repositoryPaths = try RepositoryPaths(rootPath: rootPath)
        if repositoryPaths.stateFile.exists, !force {
            throw TreeDocsError.message("treedocs.yaml already exists. Re-run with `--force` to overwrite it.")
        }

        let loaded = try configLoader.load(root: repositoryPaths.root, stateOverrides: nil)
        let scan = try scanner.scan(root: repositoryPaths.root, ignoreMatcher: IgnoreMatcher(patterns: loaded.ignorePatterns))
        let file = TreedocsFile(
            project: ProjectMetadata(
                name: repositoryPaths.root.lastComponent,
                version: "0.0.0",
                lastUpdated: currentDateString()
            ),
            signature: scan.signature,
            tree: scan.tree
        )
        try store.save(file, at: repositoryPaths.stateFile)
        return file
    }

    func sync(at rootPath: String, interactive: Bool) throws -> TreedocsFile {
        let repositoryPaths = try RepositoryPaths(rootPath: rootPath)
        let current = try store.load(at: repositoryPaths.stateFile)
        let loaded = try configLoader.load(root: repositoryPaths.root, stateOverrides: current.overrides)
        let scan = try scanner.scan(root: repositoryPaths.root, ignoreMatcher: IgnoreMatcher(patterns: loaded.ignorePatterns))
        var merged = TreedocsFile(
            project: current.project,
            overrides: current.overrides,
            signature: scan.signature,
            tree: TreeOperations.mergePreservingMetadata(scanned: scan.tree, existing: current.tree)
        )

        if interactive {
            promptForMissingDescriptions(in: &merged.tree)
        }

        try store.save(merged, at: repositoryPaths.stateFile)
        return merged
    }

    func check(at rootPath: String) throws -> CheckReport {
        let repositoryPaths = try RepositoryPaths(rootPath: rootPath)
        let current = try store.load(at: repositoryPaths.stateFile)
        let loaded = try configLoader.load(root: repositoryPaths.root, stateOverrides: current.overrides)
        let scan = try scanner.scan(root: repositoryPaths.root, ignoreMatcher: IgnoreMatcher(patterns: loaded.ignorePatterns))
        let missingDescriptions = TreeOperations.missingDescriptionPaths(in: current.tree)
        return CheckReport(
            storedSignature: current.signature,
            currentSignature: scan.signature,
            missingDescriptions: missingDescriptions,
            severity: loaded.config.resolvedCheckSeverity
        )
    }

    func inspect(at rootPath: String, path: String, recursive: Bool) throws -> InspectReport {
        let repositoryPaths = try RepositoryPaths(rootPath: rootPath)
        let file = try store.load(at: repositoryPaths.stateFile)
        let normalizedPath = RelativePath.normalize(path)
        guard let entry = TreeOperations.entry(at: normalizedPath, in: file.tree) else {
            throw TreeDocsError.message("Path not found in treedocs tree: \(normalizedPath)")
        }

        let recursiveOutput: String?
        if recursive, entry.isDirectory {
            let loaded = try configLoader.load(root: repositoryPaths.root, stateOverrides: file.overrides)
            recursiveOutput = try renderer.render(tree: file.tree, subtreePath: normalizedPath, config: loaded.config)
        } else {
            recursiveOutput = nil
        }

        return InspectReport(
            path: normalizedPath,
            entry: entry,
            linkResolution: linkResolver.resolve(path: normalizedPath, in: file.tree),
            recursiveOutput: recursiveOutput
        )
    }

    func update(
        at rootPath: String,
        path: String,
        description: String?,
        addReferences: [String],
        removeReferences: [String],
        link: String?,
        clearLink: Bool
    ) throws -> TreedocsFile {
        let repositoryPaths = try RepositoryPaths(rootPath: rootPath)
        var file = try store.load(at: repositoryPaths.stateFile)
        let normalizedPath = RelativePath.normalize(path)
        let loaded = try configLoader.load(root: repositoryPaths.root, stateOverrides: file.overrides)
        _ = try scanner.scan(root: repositoryPaths.root, ignoreMatcher: IgnoreMatcher(patterns: loaded.ignorePatterns))

        let updated = TreeOperations.updateEntry(at: normalizedPath, in: &file.tree) { entry in
            var documentation = entry.documentation ?? EntryDocumentation()
            if let description {
                documentation.description = description.trimmedNilIfEmpty
            }

            var references = documentation.references
            for reference in addReferences where !references.contains(reference) {
                references.append(reference)
            }
            references.removeAll { removeReferences.contains($0) }
            documentation.references = references
            entry.documentation = documentation.isEmpty ? nil : documentation

            if clearLink {
                entry.link = nil
            } else if let link {
                entry.link = link.trimmedNilIfEmpty
            }
        }

        guard updated else {
            throw TreeDocsError.message("Path not found in treedocs tree: \(normalizedPath)")
        }

        let scan = try scanner.scan(root: repositoryPaths.root, ignoreMatcher: IgnoreMatcher(patterns: loaded.ignorePatterns))
        file.signature = scan.signature
        try store.save(file, at: repositoryPaths.stateFile)
        return file
    }

    func renderTree(at rootPath: String, subtreePath: String?) throws -> String {
        let repositoryPaths = try RepositoryPaths(rootPath: rootPath)
        let file = try store.load(at: repositoryPaths.stateFile)
        let loaded = try configLoader.load(root: repositoryPaths.root, stateOverrides: file.overrides)
        return try renderer.render(tree: file.tree, subtreePath: subtreePath?.trimmedNilIfEmpty, config: loaded.config)
    }

    func findPath(at rootPath: String, query: String) throws -> String? {
        let repositoryPaths = try RepositoryPaths(rootPath: rootPath)
        let file = try store.load(at: repositoryPaths.stateFile)
        return TreeOperations.firstPath(matching: query, in: file.tree)
    }

    private func promptForMissingDescriptions(in tree: inout [String: TreeEntry], prefix: String = "") {
        for key in tree.keys.sorted() {
            guard var entry = tree[key] else { continue }
            let path = prefix.isEmpty ? key : prefix + "/" + key

            if entry.needsDescription {
                print("Description for \(path): ", terminator: "")
                if let answer = readLine(), let trimmed = answer.trimmedNilIfEmpty {
                    var documentation = entry.documentation ?? EntryDocumentation()
                    documentation.description = trimmed
                    entry.documentation = documentation
                }
            }

            if entry.isDirectory {
                promptForMissingDescriptions(in: &entry.children, prefix: path)
            }

            tree[key] = entry
        }
    }

    private func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
