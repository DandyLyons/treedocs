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

    func show(at rootPath: String, path: String, checkFirst: Bool) throws -> String {
        var lines: [String] = []
        if checkFirst {
            let report = try check(at: rootPath)
            if report.hasIssues {
                lines.append("Warning: treedocs discrepancies found. Run `treedocs check` for the full diagnostic report.")
            }
        }

        lines.append(try renderTree(at: rootPath, subtreePath: path))
        return lines.joined(separator: "\n")
    }

    func configFiles(at rootPath: String, under targetPath: String) throws -> [String] {
        let repositoryPaths = try RepositoryPaths(rootPath: rootPath)
        let normalizedTarget = RelativePath.normalize(targetPath)
        let searchRoot = normalizedTarget.isEmpty ? repositoryPaths.root : repositoryPaths.root + Path(normalizedTarget)
        guard searchRoot.exists else {
            throw TreeDocsError.message("Path does not exist: \(searchRoot.string)")
        }

        let fileManager = FileManager.default
        let rootString = repositoryPaths.root.string
        let searchRootString = searchRoot.string
        var results: [String] = []

        if !searchRoot.isDirectory {
            if isTreedocsConfigFile(searchRootString) {
                results.append(relativePath(for: searchRootString, root: rootString))
            }
            return results.sorted()
        }

        guard let enumerator = fileManager.enumerator(atPath: searchRootString) else {
            return []
        }

        for case let path as String in enumerator {
            let fullPath = searchRoot + Path(path)
            guard fullPath.isFile, isTreedocsConfigFile(fullPath.string) else {
                continue
            }
            results.append(relativePath(for: fullPath.string, root: rootString))
        }

        return results.sorted()
    }

    func fillPrompt(at rootPath: String) throws -> String {
        let repositoryPaths = try RepositoryPaths(rootPath: rootPath)
        _ = try store.load(at: repositoryPaths.stateFile)
        return """
        Fill missing descriptions in `treedocs.yaml` for this repository.

        Instructions:
        - Read the repository structure and the existing `treedocs.yaml`.
        - Preserve existing descriptions, references, links, project metadata, and valid schema structure unless a change is necessary to fix an inconsistency.
        - Fill missing descriptions with concise, accurate explanations based on source files, neighboring paths, names, imports, tests, and documentation.
        - Ask clarifying questions for unclear paths instead of inventing uncertain descriptions.
        - Update `treedocs.yaml` only after unclear details have been resolved or explicitly marked as needing user input.
        - Keep the result valid against `DOCS/treedocs.schema.json`.
        """
    }

    func findPath(at rootPath: String, query: String) throws -> String? {
        let repositoryPaths = try RepositoryPaths(rootPath: rootPath)
        let file = try store.load(at: repositoryPaths.stateFile)
        return TreeOperations.firstPath(matching: query, in: file.tree)
    }

    private func isTreedocsConfigFile(_ path: String) -> Bool {
        path.hasSuffix("/treedocs.yaml")
            || path.hasSuffix("/.treedocs/config.yaml")
            || path.hasSuffix("/.treedocs/.treedocs_ignore")
    }

    private func relativePath(for path: String, root: String) -> String {
        if path == root {
            return "."
        }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return path
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
