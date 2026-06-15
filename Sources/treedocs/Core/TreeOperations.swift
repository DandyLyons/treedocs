import Foundation

/// Provides pure operations for documented tree entries.
///
/// `TreeOperations` centralizes traversal, lookup, mutation, flattening, and merge behavior for
/// `TreeEntry` dictionaries. The operations do not perform filesystem I/O and are safe to reuse
/// from parsing, scanning, rendering, and service code.
enum TreeOperations {
    /// Inserts an entry at a component path.
    ///
    /// Existing entries are merged instead of replaced: missing documentation and links are filled,
    /// directory status is preserved, and child entries are copied into the existing node. Missing
    /// intermediate directories are created automatically.
    ///
    /// - Parameters:
    ///   - entry: The tree entry to insert.
    ///   - components: The normalized path components identifying where the entry belongs.
    ///   - tree: The tree dictionary to mutate.
    static func insert(entry: TreeEntry, at components: [String], into tree: inout [String: TreeEntry]) {
        guard let first = components.first else { return }

        if components.count == 1 {
            if var existing = tree[first] {
                existing.documentation = entry.documentation ?? existing.documentation
                existing.link = entry.link ?? existing.link
                existing.isDirectory = existing.isDirectory || entry.isDirectory
                for (key, value) in entry.children {
                    existing.children[key] = value
                }
                tree[first] = existing
            } else {
                tree[first] = entry
            }
            return
        }

        var parent = tree[first] ?? TreeEntry(children: [:], isDirectory: true)
        parent.isDirectory = true
        insert(entry: entry, at: Array(components.dropFirst()), into: &parent.children)
        tree[first] = parent
    }

    /// Looks up an entry at a relative path.
    ///
    /// An empty path represents the repository root and returns a synthetic directory entry whose
    /// children are the supplied tree. Non-empty paths are normalized before traversal.
    ///
    /// - Parameters:
    ///   - relativePath: The repository-relative path to resolve.
    ///   - tree: The tree to search.
    /// - Returns: The matching entry, the synthetic root entry for an empty path, or `nil` when no entry exists.
    static func entry(at relativePath: String, in tree: [String: TreeEntry]) -> TreeEntry? {
        let components = RelativePath.components(for: relativePath)
        guard !components.isEmpty else {
            return TreeEntry(children: tree, isDirectory: true)
        }

        var currentTree = tree
        var currentEntry: TreeEntry?
        for component in components {
            guard let next = currentTree[component] else {
                return nil
            }
            currentEntry = next
            currentTree = next.children
        }
        return currentEntry
    }

    /// Mutates an entry at a relative path.
    ///
    /// The mutation closure receives a copy of the matching entry and the updated value is written
    /// back into the tree. Parent nodes are preserved while recursive updates are applied.
    ///
    /// - Parameters:
    ///   - relativePath: The repository-relative path of the entry to mutate.
    ///   - tree: The tree to update.
    ///   - mutate: A closure that modifies the matched entry in place.
    /// - Returns: `true` when an entry was found and updated; otherwise, `false`.
    @discardableResult
    static func updateEntry(at relativePath: String, in tree: inout [String: TreeEntry], mutate: (inout TreeEntry) -> Void) -> Bool {
        let components = RelativePath.components(for: relativePath)
        guard let first = components.first else {
            return false
        }

        if components.count == 1 {
            guard var entry = tree[first] else {
                return false
            }
            mutate(&entry)
            tree[first] = entry
            return true
        }

        guard var parent = tree[first] else {
            return false
        }
        let updated = updateEntry(at: Array(components.dropFirst()).joined(separator: "/"), in: &parent.children, mutate: mutate)
        tree[first] = parent
        return updated
    }

    /// Flattens a tree into sorted path-entry pairs.
    ///
    /// Paths are emitted in lexicographic order and include directory entries before their children.
    /// The optional prefix is prepended to generated child paths during recursive calls.
    ///
    /// - Parameters:
    ///   - tree: The tree to flatten.
    ///   - prefix: The path prefix to apply to emitted entries.
    /// - Returns: A sorted list of `(path, entry)` tuples.
    static func flatten(_ tree: [String: TreeEntry], prefix: String = "") -> [(String, TreeEntry)] {
        var result: [(String, TreeEntry)] = []

        for key in tree.keys.sorted() {
            guard let entry = tree[key] else { continue }
            let path = prefix.isEmpty ? key : prefix + "/" + key
            result.append((path, entry))
            if entry.isDirectory {
                result.append(contentsOf: flatten(entry.children, prefix: path))
            }
        }

        return result
    }

    /// Collects stable paths for signature generation.
    ///
    /// File paths are appended as-is and directory paths receive a trailing slash. The resulting
    /// strings are deterministic when callers start with an empty result array.
    ///
    /// - Parameters:
    ///   - tree: The tree to walk.
    ///   - prefix: The current path prefix used during recursion.
    ///   - result: The array that receives normalized paths.
    static func collectNormalizedPaths(in tree: [String: TreeEntry], prefix: String = "", into result: inout [String]) {
        for key in tree.keys.sorted() {
            guard let entry = tree[key] else { continue }
            let path = prefix.isEmpty ? key : prefix + "/" + key
            result.append(entry.isDirectory ? path + "/" : path)
            if entry.isDirectory {
                collectNormalizedPaths(in: entry.children, prefix: path, into: &result)
            }
        }
    }

    /// Finds entries that still need descriptions.
    ///
    /// Entries with empty descriptions require documentation unless they link to another entry.
    /// Returned paths use the same relative format as rendered tree paths.
    ///
    /// - Parameter tree: The tree to inspect.
    /// - Returns: Relative paths for entries that need descriptions.
    static func missingDescriptionPaths(in tree: [String: TreeEntry]) -> [String] {
        flatten(tree)
            .filter { _, entry in entry.needsDescription }
            .map(\.0)
    }

    /// Applies description updates to existing tree entries.
    ///
    /// Description text is trimmed and blank descriptions are ignored. Existing references and links
    /// are preserved while the description field is replaced for matching paths.
    ///
    /// - Parameters:
    ///   - descriptions: Description text keyed by relative tree path.
    ///   - tree: The tree to update in place.
    /// - Returns: Paths that were found and updated.
    @discardableResult
    static func applyDescriptions(_ descriptions: [String: String], to tree: inout [String: TreeEntry]) -> [String] {
        var updatedPaths: [String] = []

        for path in descriptions.keys.sorted() {
            guard let description = descriptions[path]?.trimmedNilIfEmpty else {
                continue
            }

            let updated = updateEntry(at: path, in: &tree) { entry in
                var documentation = entry.documentation ?? EntryDocumentation()
                documentation.description = description
                entry.documentation = documentation
            }
            if updated {
                updatedPaths.append(path)
            }
        }

        return updatedPaths
    }

    /// Finds paths present in the scanned filesystem but absent from stored documentation.
    static func missingPaths(stored: [String: TreeEntry], scanned: [String: TreeEntry]) -> [String] {
        sortedDifference(lhs: pathSet(scanned), rhs: pathSet(stored))
    }

    /// Finds paths present in stored documentation but absent from the scanned filesystem.
    static func extraPaths(stored: [String: TreeEntry], scanned: [String: TreeEntry]) -> [String] {
        sortedDifference(lhs: pathSet(stored), rhs: pathSet(scanned))
    }

    /// Finds paths whose stored file-or-directory kind differs from the scanned filesystem kind.
    static func changedPaths(stored: [String: TreeEntry], scanned: [String: TreeEntry]) -> [String] {
        let storedEntries = entryMap(stored)
        let scannedEntries = entryMap(scanned)
        return storedEntries.keys.filter { path in
            guard let storedEntry = storedEntries[path], let scannedEntry = scannedEntries[path] else {
                return false
            }
            return storedEntry.isDirectory != scannedEntry.isDirectory
        }.sorted()
    }

    /// Finds stored descendant paths that are owned by nested `treedocs.yaml` boundaries.
    static func shadowedPaths(stored: [String: TreeEntry], nestedBoundaries: [String]) -> [String] {
        let storedPaths = pathSet(stored)
        return storedPaths.filter { path in
            nestedBoundaries.contains { boundary in
                path.hasPrefix(boundary + "/")
            }
        }.sorted()
    }

    /// Merges scanned structure with existing metadata.
    ///
    /// The scanned tree is authoritative for filesystem structure. Existing descriptions,
    /// references, and links are preserved only when the scanned and existing entries have the same
    /// file-or-directory kind.
    ///
    /// - Parameters:
    ///   - scanned: The current filesystem tree produced by the scanner.
    ///   - existing: The previously stored documentation tree.
    /// - Returns: A tree with current structure and preserved compatible metadata.
    static func mergePreservingMetadata(scanned: [String: TreeEntry], existing: [String: TreeEntry]) -> [String: TreeEntry] {
        var merged: [String: TreeEntry] = [:]
        for key in scanned.keys.sorted() {
            guard let scannedEntry = scanned[key] else { continue }
            let existingEntry = existing[key]
            merged[key] = mergeEntry(scanned: scannedEntry, existing: existingEntry)
        }
        return merged
    }

    /// Finds the first path matching a query.
    ///
    /// Matching is case-insensitive and tries exact path, path prefix, path substring, and finally
    /// description substring matches. Path-based matches are evaluated before description matches.
    ///
    /// - Parameters:
    ///   - query: The search text.
    ///   - tree: The tree to search.
    /// - Returns: The first matching relative path, or `nil` when nothing matches.
    static func firstPath(matching query: String, in tree: [String: TreeEntry]) -> String? {
        let normalizedQuery = query.lowercased()
        let entries = flatten(tree).sorted { $0.0 < $1.0 }
        let allPaths = entries.map(\.0)

        if let exact = allPaths.first(where: { $0.lowercased() == normalizedQuery }) {
            return exact
        }
        if let prefix = allPaths.first(where: { $0.lowercased().hasPrefix(normalizedQuery) }) {
            return prefix
        }
        if let contains = allPaths.first(where: { $0.lowercased().contains(normalizedQuery) }) {
            return contains
        }

        return entries.first { _, entry in
            entry.description?.lowercased().contains(normalizedQuery) == true
        }?.0
    }

    /// Merges compatible entry metadata into a scanned entry.
    ///
    /// Metadata is preserved only when both entries describe the same kind of path. Directory
    /// children are merged recursively so removed filesystem paths are not retained.
    ///
    /// - Parameters:
    ///   - scanned: The scanned entry that defines current structure.
    ///   - existing: The previously stored entry, if any.
    /// - Returns: The scanned entry with compatible metadata restored.
    private static func mergeEntry(scanned: TreeEntry, existing: TreeEntry?) -> TreeEntry {
        var merged = scanned
        if let existing, existing.isDirectory == scanned.isDirectory {
            merged.documentation = existing.documentation
            merged.link = existing.link
            if scanned.isDirectory {
                merged.children = mergePreservingMetadata(scanned: scanned.children, existing: existing.children)
            }
        }
        return merged
    }

    private static func pathSet(_ tree: [String: TreeEntry]) -> Set<String> {
        Set(flatten(tree).map(\.0))
    }

    private static func entryMap(_ tree: [String: TreeEntry]) -> [String: TreeEntry] {
        Dictionary(uniqueKeysWithValues: flatten(tree))
    }

    private static func sortedDifference(lhs: Set<String>, rhs: Set<String>) -> [String] {
        lhs.subtracting(rhs).sorted()
    }
}
