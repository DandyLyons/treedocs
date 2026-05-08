import Foundation

enum TreeOperations {
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

    static func missingDescriptionPaths(in tree: [String: TreeEntry]) -> [String] {
        flatten(tree)
            .filter { _, entry in entry.needsDescription }
            .map(\.0)
    }

    static func mergePreservingMetadata(scanned: [String: TreeEntry], existing: [String: TreeEntry]) -> [String: TreeEntry] {
        var merged: [String: TreeEntry] = [:]
        for key in scanned.keys.sorted() {
            guard let scannedEntry = scanned[key] else { continue }
            let existingEntry = existing[key]
            merged[key] = mergeEntry(scanned: scannedEntry, existing: existingEntry)
        }
        return merged
    }

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
}
