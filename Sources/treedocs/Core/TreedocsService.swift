import Foundation
import PathKit

/// Summarizes validation results for a repository's stored tree documentation.
///
/// A check report compares the signature persisted in `treedocs.yaml` with the current scanned
/// filesystem signature and records entries that still need descriptions. Commands use `severity`
/// to decide whether reported issues should fail the process.
struct CheckReport {
    /// The signature currently stored in `treedocs.yaml`, if one exists.
    var storedSignature: String?

    /// The signature calculated from the current filesystem scan.
    var currentSignature: String

    /// Relative paths for entries that need descriptions.
    var missingDescriptions: [String]

    /// The configured failure policy for check results.
    var severity: CheckSeverity

    /// Whether the stored signature differs from the current signature.
    var hasSignatureDrift: Bool {
        storedSignature != currentSignature
    }

    /// Whether the report contains any actionable issue.
    var hasIssues: Bool {
        hasSignatureDrift || !missingDescriptions.isEmpty
    }

    /// Whether the configured severity should fail the command.
    var shouldFail: Bool {
        hasIssues && severity == .error
    }
}

/// Describes a single inspected tree entry and any resolved linked content.
///
/// Inspection combines the normalized requested path, the entry stored at that path, link
/// resolution details, and optional recursive render output for directory entries.
struct InspectReport {
    /// The normalized path that was inspected.
    var path: String

    /// The tree entry found at `path`.
    var entry: TreeEntry

    /// The result of resolving the entry's link, if it has one.
    var linkResolution: LinkResolution

    /// Rendered child output when recursive directory rendering was requested.
    var recursiveOutput: String?
}

/// Coordinates repository scanning, state storage, rendering, and tree mutations.
///
/// `TreedocsService` is the command-facing facade for core behavior. It validates repository paths,
/// loads configuration and state, delegates structural operations to specialized helpers, and saves
/// updated `treedocs.yaml` files when commands mutate state.
struct TreedocsService {
    var store = TreedocsFileStore()
    var configLoader = ConfigLoader()
    var scanner = TreeScanner()
    var renderer = TreeRenderer()
    var linkResolver = LinkResolver()

    /// Creates a fresh `treedocs.yaml` for a repository.
    ///
    /// The repository is scanned using resolved configuration, initial project metadata is created,
    /// and the resulting state file is written to the repository root. Existing state files are
    /// protected unless `force` is `true`.
    ///
    /// - Parameters:
    ///   - rootPath: The repository root path supplied by the caller.
    ///   - force: Whether to overwrite an existing `treedocs.yaml` file.
    /// - Returns: The newly created state model.
    /// - Throws: `TreeDocsError` when the path is invalid or state already exists without `force`, or any filesystem/configuration error encountered while scanning or saving.
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

    /// Reconciles `treedocs.yaml` with the current filesystem.
    ///
    /// The scanner supplies the current structure, then existing descriptions, references, and links
    /// are preserved for compatible paths. In interactive mode, missing descriptions are requested
    /// from standard input before the merged file is saved.
    ///
    /// - Parameters:
    ///   - rootPath: The repository root path supplied by the caller.
    ///   - interactive: Whether to prompt for missing descriptions while syncing.
    /// - Returns: The saved, merged state model.
    /// - Throws: `TreeDocsError` for invalid paths or missing state, plus filesystem/configuration errors from loading, scanning, or saving.
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

    /// Checks whether stored documentation is current.
    ///
    /// The check compares the persisted signature against a fresh scan and identifies entries that
    /// still require descriptions. It does not mutate or save state.
    ///
    /// - Parameter rootPath: The repository root path supplied by the caller.
    /// - Returns: A report containing signature drift, missing descriptions, and configured severity.
    /// - Throws: `TreeDocsError` for invalid paths or missing state, plus filesystem/configuration errors from loading or scanning.
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

    /// Inspects a documented path.
    ///
    /// The requested path is normalized before lookup. Link metadata is resolved into a structured
    /// result, and directory entries can optionally include recursively rendered child output.
    ///
    /// - Parameters:
    ///   - rootPath: The repository root path supplied by the caller.
    ///   - path: The documented path to inspect.
    ///   - recursive: Whether to include rendered child output when `path` is a directory.
    /// - Returns: Inspection details for the normalized path.
    /// - Throws: `TreeDocsError` when the repository or requested tree path cannot be found, or when loading/rendering fails.
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

    /// Updates metadata for a documented entry.
    ///
    /// Description text is trimmed and empty descriptions are removed. Added references are
    /// de-duplicated, requested references are removed, and link metadata can be set or cleared.
    /// The tree signature is refreshed from a current scan before saving.
    ///
    /// - Parameters:
    ///   - rootPath: The repository root path supplied by the caller.
    ///   - path: The documented path to update.
    ///   - description: Optional replacement description text.
    ///   - addReferences: References to append if not already present.
    ///   - removeReferences: References to remove from the entry.
    ///   - link: Optional replacement link target.
    ///   - clearLink: Whether to remove any existing link target.
    /// - Returns: The saved state model after mutation.
    /// - Throws: `TreeDocsError` when the repository, state file, or requested tree path cannot be found, or when loading, scanning, or saving fails.
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

    /// Renders the full documentation tree or a requested subtree.
    ///
    /// Rendering uses the resolved configuration from defaults, config files, and state overrides.
    /// Empty subtree paths are treated as requests for the full tree.
    ///
    /// - Parameters:
    ///   - rootPath: The repository root path supplied by the caller.
    ///   - subtreePath: An optional tree path to render instead of the full tree.
    /// - Returns: A newline-separated textual representation of the requested tree.
    /// - Throws: `TreeDocsError` when repository state or the requested subtree cannot be found, or when configuration loading fails.
    func renderTree(at rootPath: String, subtreePath: String?) throws -> String {
        let repositoryPaths = try RepositoryPaths(rootPath: rootPath)
        let file = try store.load(at: repositoryPaths.stateFile)
        let loaded = try configLoader.load(root: repositoryPaths.root, stateOverrides: file.overrides)
        return try renderer.render(tree: file.tree, subtreePath: subtreePath?.trimmedNilIfEmpty, config: loaded.config)
    }

    /// Renders documentation for a path, optionally checking for drift first.
    ///
    /// When `checkFirst` is enabled, the output begins with a warning if the repository has
    /// signature drift or missing descriptions. Rendering still proceeds after warnings.
    ///
    /// - Parameters:
    ///   - rootPath: The repository root path supplied by the caller.
    ///   - path: The tree path to render.
    ///   - checkFirst: Whether to run a non-mutating check before rendering.
    /// - Returns: Rendered output, optionally prefixed with a warning line.
    /// - Throws: Any error thrown by checking or rendering the requested tree.
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

    /// Finds treedocs configuration and state files beneath a repository path.
    ///
    /// Files are returned as repository-relative paths. If the target is itself a matching file, the
    /// returned list contains only that file; otherwise directories are searched recursively.
    ///
    /// - Parameters:
    ///   - rootPath: The repository root path supplied by the caller.
    ///   - targetPath: The file or directory path to inspect, relative to the repository root.
    /// - Returns: Sorted repository-relative paths for matching treedocs files.
    /// - Throws: `TreeDocsError` when the repository or target path does not exist.
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

    /// Generates a maintenance prompt for filling missing descriptions.
    ///
    /// The prompt is returned only after confirming that the repository has an existing
    /// `treedocs.yaml`, which keeps the generated instructions tied to a real state file.
    ///
    /// - Parameter rootPath: The repository root path supplied by the caller.
    /// - Returns: A prompt that instructs an assistant how to fill missing descriptions safely.
    /// - Throws: `TreeDocsError` when the repository path or state file is missing.
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

    /// Finds the first documented path matching a query.
    ///
    /// Search behavior is delegated to `TreeOperations.firstPath(matching:in:)`, which prioritizes
    /// path matches before description matches.
    ///
    /// - Parameters:
    ///   - rootPath: The repository root path supplied by the caller.
    ///   - query: The case-insensitive search text.
    /// - Returns: The first matching documented path, or `nil` when nothing matches.
    /// - Throws: `TreeDocsError` when the repository path or state file is missing.
    func findPath(at rootPath: String, query: String) throws -> String? {
        let repositoryPaths = try RepositoryPaths(rootPath: rootPath)
        let file = try store.load(at: repositoryPaths.stateFile)
        return TreeOperations.firstPath(matching: query, in: file.tree)
    }

    /// Checks whether a path is a treedocs-managed configuration file.
    ///
    /// Matching is suffix-based because callers may pass absolute paths while results are reported
    /// relative to the repository root.
    ///
    /// - Parameter path: The filesystem path to classify.
    /// - Returns: `true` when the path is `treedocs.yaml`, `.treedocs/config.yaml`, or `.treedocs/.treedocs_ignore`.
    private func isTreedocsConfigFile(_ path: String) -> Bool {
        path.hasSuffix("/treedocs.yaml")
            || path.hasSuffix("/.treedocs/config.yaml")
            || path.hasSuffix("/.treedocs/.treedocs_ignore")
    }

    /// Converts a path to repository-relative form when possible.
    ///
    /// Paths outside the repository root are returned unchanged, which preserves diagnostic value for
    /// unexpected enumerator results.
    ///
    /// - Parameters:
    ///   - path: The path to convert.
    ///   - root: The absolute repository root path.
    /// - Returns: `.` for the root itself, a relative path for descendants, or the original path otherwise.
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

    /// Prompts for missing descriptions in a tree.
    ///
    /// The traversal is deterministic so prompts appear in sorted path order. Blank or whitespace-only
    /// answers are ignored, leaving the entry marked as needing a description.
    ///
    /// - Parameters:
    ///   - tree: The tree to update in place.
    ///   - prefix: The current path prefix used while recursing.
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

    /// Formats the current date for project metadata.
    ///
    /// Dates are formatted with a Gregorian calendar, POSIX locale, and UTC time zone to keep generated
    /// metadata stable across user environments.
    ///
    /// - Returns: The current date as `yyyy-MM-dd`.
    private func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
