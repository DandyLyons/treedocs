import Foundation
import MarkdownUtilitiesCore
import PathKit

/// One fully rendered README that is ready for exclusive creation.
struct PlannedReadmeStubCreation {
    /// Absolute destination for the new README.
    let path: Path

    /// Repository-relative destination used in command output and diagnostics.
    let relativePath: String

    /// Complete Markdown source rendered through `MarkdownUtilitiesCore`.
    let source: String
}

/// Creates staged README files without replacing any existing filesystem item.
protocol ReadmeStubWriting {
    /// Verifies all destinations, creates each file exclusively, and rolls back earlier creations on failure.
    func write(_ creations: [PlannedReadmeStubCreation]) throws
}

/// Applies a set of README creations as one recoverable operation.
struct TransactionalReadmeStubWriter: ReadmeStubWriting {
    private let fileManager: FileManager
    private let create: (String, Path) throws -> Void
    private let remove: (Path) throws -> Void

    /// Creates a writer with injectable filesystem operations for failure-path testing.
    init(
        fileManager: FileManager = .default,
        create: @escaping (String, Path) throws -> Void = { source, path in
            try Data(source.utf8).write(to: path.url, options: .withoutOverwriting)
        },
        remove: @escaping (Path) throws -> Void = { path in
            try FileManager.default.removeItem(atPath: path.string)
        }
    ) {
        self.fileManager = fileManager
        self.create = create
        self.remove = remove
    }

    /// Checks every staged destination before writing and removes only files created by this invocation if a write fails.
    func write(_ creations: [PlannedReadmeStubCreation]) throws {
        for creation in creations where fileManager.fileExists(atPath: creation.path.string) {
            throw TreeDocsError.message(
                "README destination appeared before writing: \(creation.relativePath). No files were created."
            )
        }

        var completed: [PlannedReadmeStubCreation] = []
        do {
            for creation in creations {
                try create(creation.source, creation.path)
                completed.append(creation)
            }
        } catch {
            var rollbackFailures: [String] = []
            for creation in completed.reversed() {
                do {
                    try remove(creation.path)
                } catch {
                    rollbackFailures.append(creation.relativePath)
                }
            }

            let rollbackSummary = rollbackFailures.isEmpty
                ? "All README files created earlier by this invocation were removed."
                : "Rollback failed for: \(rollbackFailures.joined(separator: ", "))."
            throw TreeDocsError.message(
                "README creation failed: \(error.localizedDescription) \(rollbackSummary)"
            )
        }
    }
}

/// Created and skipped source files from `createDoc` or its `createREADME` alias.
struct CreateReadmeResult: Equatable {
    /// Repository-relative selected source paths created by the command.
    var createdPaths: [String]

    /// Repository-relative selected source paths that already existed with the exact filename spelling.
    var skippedPaths: [String]
}

/// Discovers eligible directories and renders selected documentation sources from stored metadata.
struct ReadmeStubCreator {
    private let fileManager = FileManager.default

    /// Creates selected documentation sources without modifying the repository's state file.
    ///
    /// Existing sources are skipped. New stubs use `file:` frontmatter, folder-relative references,
    /// and a directory heading. Rendering completes before the writer receives any creations.
    ///
    /// - Parameters:
    ///   - repositoryPaths: Validated repository paths used to resolve targets.
    ///   - targetPath: Directory to document, relative to the root or absolute within the repository.
    ///   - recursive: Whether to include eligible descendant directories.
    ///   - file: Canonical state supplying project and folder metadata.
    ///   - ignoreMatcher: Resolved exclusions for directories and destination files.
    ///   - sources: The same resolved ``FolderDocumentationSourceSelection`` used by the scanner.
    ///   - writer: Applies staged creations without overwriting existing files.
    /// - Returns: Created and skipped paths in discovery order.
    /// - Throws: Invalid or excluded targets, targets below nested roots, excluded explicit sources,
    ///   reference conversion errors, or filesystem and writer failures.
    func create(
        repositoryPaths: RepositoryPaths,
        targetPath: String,
        recursive: Bool,
        file: TreedocsFile,
        ignoreMatcher: IgnoreMatcher,
        sources: FolderDocumentationSourceSelection = FolderDocumentationSourceSelection(),
        writer: any ReadmeStubWriting
    ) throws -> CreateReadmeResult {
        let target = try resolveTarget(targetPath, in: repositoryPaths)
        let directoryPaths = try discoverDirectories(
            root: repositoryPaths.root,
            target: target,
            recursive: recursive,
            ignoreMatcher: ignoreMatcher
        )

        var creations: [PlannedReadmeStubCreation] = []
        var skippedPaths: [String] = []

        for directoryPath in directoryPaths {
            let filename = sources.filename(for: directoryPath)
            let readmePath = directoryPath.isEmpty ? filename : directoryPath + "/" + filename
            if ignoreMatcher.shouldIgnore(relativePath: readmePath, isDirectory: false) {
                if sources.isExplicit(directoryPath) {
                    throw TreeDocsError.message("Selected documentation source \(readmePath) is excluded. Adjust ignore rules or overrides.documentation_sources.")
                }
                continue
            }
            let destination = repositoryPaths.root + Path(readmePath)
            let directory = directoryPath.isEmpty ? repositoryPaths.root : repositoryPaths.root + Path(directoryPath)
            if try containsExactReadme(in: directory, filename: filename) {
                skippedPaths.append(readmePath)
                continue
            }

            creations.append(PlannedReadmeStubCreation(
                path: destination,
                relativePath: readmePath,
                source: try renderReadme(
                    directoryPath: directoryPath,
                    repositoryRoot: repositoryPaths.root,
                    file: file
                )
            ))
        }

        try writer.write(creations)
        return CreateReadmeResult(
            createdPaths: creations.map(\.relativePath),
            skippedPaths: skippedPaths
        )
    }

    /// Resolves a required directory relative to the repository while rejecting missing, file, and escaping targets.
    private func resolveTarget(_ targetPath: String, in repositoryPaths: RepositoryPaths) throws -> Path {
        guard targetPath.trimmedNilIfEmpty != nil else {
            throw TreeDocsError.message("The target directory path cannot be blank.")
        }

        let rawTarget = Path(targetPath)
        let lexicalTarget = (rawTarget.isAbsolute ? rawTarget : repositoryPaths.root + rawTarget).absolute()
        let statePath = repositoryPaths.stateFile.absolute()
        if lexicalTarget == statePath {
            throw TreeDocsError.message("The repository state file is not a directory: treedocs.yaml")
        }
        guard lexicalTarget.exists else {
            throw TreeDocsError.message("Directory does not exist: \(directoryDisplayPath(lexicalTarget.string))")
        }
        guard lexicalTarget.isDirectory else {
            throw TreeDocsError.message("Target is not a directory: \(lexicalTarget.string)")
        }

        let resolvedRoot = resolvedFilesystemPath(repositoryPaths.root)
        let resolvedTarget = resolvedFilesystemPath(lexicalTarget)
        guard isInsideRepository(resolvedTarget, root: resolvedRoot) else {
            throw TreeDocsError.message(
                "Directory is outside the selected repository: \(directoryDisplayPath(resolvedTarget))"
            )
        }
        return lexicalTarget
    }

    /// Returns the target and, when requested, visible descendants in deterministic depth-first order.
    private func discoverDirectories(
        root: Path,
        target: Path,
        recursive: Bool,
        ignoreMatcher: IgnoreMatcher
    ) throws -> [String] {
        let targetRelativePath = relativePath(for: target, root: root)
        let components = RelativePath.components(for: targetRelativePath)
        for index in components.indices {
            let count = index + 1
            let ancestor = components.prefix(count).joined(separator: "/")
            if ignoreMatcher.shouldIgnore(relativePath: ancestor, isDirectory: true) {
                throw TreeDocsError.message("Documentation target \(ancestor)/ is excluded. Adjust ignore rules before creating documentation.")
            }
            if count < components.count, containsStateFile(root + Path(ancestor)) {
                throw TreeDocsError.message("Documentation target belongs to nested root \(ancestor)/. Select that repository with --path.")
            }
        }
        guard recursive else {
            return [targetRelativePath]
        }

        var result = [targetRelativePath]
        if !targetRelativePath.isEmpty, containsStateFile(target) {
            return result
        }

        let resolvedRoot = resolvedFilesystemPath(root)
        var visited = Set([resolvedFilesystemPath(target)])
        try appendDescendants(
            root: root,
            directory: target,
            relativePath: targetRelativePath,
            resolvedRoot: resolvedRoot,
            ignoreMatcher: ignoreMatcher,
            visited: &visited,
            result: &result
        )
        return result
    }

    /// Recursively appends eligible directories while stopping at ignores, external symlinks, and nested state boundaries.
    private func appendDescendants(
        root: Path,
        directory: Path,
        relativePath: String,
        resolvedRoot: String,
        ignoreMatcher: IgnoreMatcher,
        visited: inout Set<String>,
        result: inout [String]
    ) throws {
        let childNames = try fileManager.contentsOfDirectory(atPath: directory.string).sorted()
        for childName in childNames {
            let childRelativePath = relativePath.isEmpty ? childName : relativePath + "/" + childName
            let child = root + Path(childRelativePath)
            guard child.isDirectory else {
                continue
            }
            guard !ignoreMatcher.shouldIgnore(relativePath: childRelativePath, isDirectory: true) else {
                continue
            }

            let resolvedChild = resolvedFilesystemPath(child)
            guard isInsideRepository(resolvedChild, root: resolvedRoot) else {
                continue
            }
            guard visited.insert(resolvedChild).inserted else {
                continue
            }

            result.append(childRelativePath)
            if containsStateFile(child) {
                continue
            }
            try appendDescendants(
                root: root,
                directory: child,
                relativePath: childRelativePath,
                resolvedRoot: resolvedRoot,
                ignoreMatcher: ignoreMatcher,
                visited: &visited,
                result: &result
            )
        }
    }

    /// Renders one structured README through `MarkdownUtilitiesCore`.
    private func renderReadme(directoryPath: String, repositoryRoot: Path, file: TreedocsFile) throws -> String {
        var entries: [(String, FrontMatterValue)] = []

        if !directoryPath.isEmpty,
           let entry = TreeOperations.entry(at: directoryPath, in: file.tree),
           entry.isDirectory {
            if let description = entry.description?.trimmedNilIfEmpty {
                entries.append(("description", .string(description)))
            }

            var seenReferences = Set<String>()
            let references = try entry.references.compactMap { reference -> String? in
                guard let trimmed = reference.trimmedNilIfEmpty, seenReferences.insert(trimmed).inserted else {
                    return nil
                }
                return try ReadmeReferenceNormalizer.readmeReference(trimmed, folderPath: directoryPath)
            }
            if !references.isEmpty {
                entries.append(("references", .array(references.map(FrontMatterValue.string))))
            }
        }

        let readmeDescription = directoryPath.isEmpty
            ? "Project overview and documentation."
            : "Overview and documentation for \(directoryPath)/."
        entries.append((
            "file",
            .object(FrontMatter([("description", .string(readmeDescription))]))
        ))

        let heading: String
        if directoryPath.isEmpty {
            heading = file.project.name?.trimmedNilIfEmpty ?? repositoryRoot.lastComponent
        } else {
            heading = Path(directoryPath).lastComponent
        }

        let document = MarkdownDocument(
            frontMatter: FrontMatter(entries),
            body: "\n# \(heading)\n",
            frontMatterFormat: .yaml
        )
        let rendered = try document.render()
        return rendered.hasSuffix("\n") ? rendered : rendered + "\n"
    }

    private func containsStateFile(_ directory: Path) -> Bool {
        (directory + Path("treedocs.yaml")).isFile
    }

    /// Checks the selected filename's exact spelling, including on case-insensitive filesystems.
    private func containsExactReadme(in directory: Path, filename: String) throws -> Bool {
        guard try fileManager.contentsOfDirectory(atPath: directory.string).contains(filename) else {
            return false
        }
        return (directory + Path(filename)).isFile
    }

    private func relativePath(for path: Path, root: Path) -> String {
        let rootString = root.absolute().string
        let pathString = path.absolute().string
        guard pathString != rootString else {
            return ""
        }
        return String(pathString.dropFirst(rootString.count + 1))
            .replacingOccurrences(of: "\\", with: "/")
    }

    private func resolvedFilesystemPath(_ path: Path) -> String {
        path.url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func isInsideRepository(_ path: String, root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    private func directoryDisplayPath(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }
}
