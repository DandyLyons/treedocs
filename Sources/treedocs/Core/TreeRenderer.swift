import Foundation

/// Renders documented tree entries as human-readable text.
///
/// The renderer is responsible only for presentation. It does not resolve links or mutate entries;
/// it formats labels, optional reference/link markers, indentation, alignment, and truncated
/// descriptions according to `TreedocsConfig`.
struct TreeRenderer {
    /// Renders a tree or subtree.
    ///
    /// When `subtreePath` names a directory, only that directory's children are rendered with the
    /// requested path as their prefix. When it names a file, a single-file tree is rendered.
    ///
    /// - Parameters:
    ///   - tree: The full documentation tree to render from.
    ///   - subtreePath: An optional path limiting output to one subtree or file.
    ///   - config: Display configuration controlling indentation, alignment, and description length.
    /// - Returns: A newline-separated textual representation of the requested tree.
    /// - Throws: `TreeDocsError` when `subtreePath` does not exist in `tree`.
    func render(tree: [String: TreeEntry], subtreePath: String?, config: TreedocsConfig) throws -> String {
        let renderedTree: [String: TreeEntry]
        let pathPrefix: String

        if let subtreePath, let normalized = RelativePath.normalize(subtreePath).trimmedNilIfEmpty {
            guard let entry = TreeOperations.entry(at: normalized, in: tree) else {
                throw TreeDocsError.message("Path not found in treedocs tree: \(normalized)")
            }

            if entry.isDirectory {
                renderedTree = entry.children
                pathPrefix = normalized
            } else {
                renderedTree = [RelativePath.components(for: normalized).last ?? normalized: entry]
                pathPrefix = RelativePath.components(for: normalized).dropLast().joined(separator: "/")
            }
        } else {
            renderedTree = tree
            pathPrefix = ""
        }

        let flattened = flattenForRender(tree: renderedTree, prefix: pathPrefix, depth: 0, config: config)
        let labelWidth = config.resolvedAlignColumns ? flattened.map { $0.label.count }.max() ?? 0 : 0
        let rendered = flattened.map { item in
            let label = config.resolvedAlignColumns ? item.label.padding(toLength: labelWidth, withPad: " ", startingAt: 0) : item.label
            if let description = item.description {
                return "\(label)  \(description)"
            }
            return label
        }
        return rendered.joined(separator: "\n")
    }

    /// Flattens a nested tree into indented render rows.
    ///
    /// Each returned row contains a fully decorated label and the already-truncated description text,
    /// leaving column alignment to the top-level render method.
    ///
    /// - Parameters:
    ///   - tree: The tree or subtree to flatten.
    ///   - prefix: The logical path prefix for entries in `tree`.
    ///   - depth: The current nesting depth used for indentation.
    ///   - config: Display configuration for indentation and description length.
    /// - Returns: Ordered render rows containing labels and optional descriptions.
    private func flattenForRender(tree: [String: TreeEntry], prefix: String, depth: Int, config: TreedocsConfig) -> [(label: String, description: String?)] {
        var lines: [(String, String?)] = []

        for key in tree.keys.sorted() {
            guard let entry = tree[key] else { continue }
            let path = prefix.isEmpty ? key : prefix + "/" + key
            let indent = String(repeating: " ", count: depth * config.resolvedIndentSize)
            let marker = entry.isDirectory ? "\(key)/" : key
            let label = indent + decorate(label: marker, entry: entry)
            lines.append((label, descriptionText(for: entry, config: config)))
            if entry.isDirectory {
                lines.append(contentsOf: flattenForRender(tree: entry.children, prefix: path, depth: depth + 1, config: config))
            }
        }

        return lines
    }

    /// Adds metadata markers to a rendered label.
    ///
    /// Reference and link markers are compact because the tree output is intended to remain readable
    /// in terminals.
    ///
    /// - Parameters:
    ///   - label: The base path label, including any indentation or directory suffix.
    ///   - entry: The entry whose metadata should be reflected in the label.
    /// - Returns: The decorated label.
    private func decorate(label: String, entry: TreeEntry) -> String {
        var suffixes: [String] = []
        if entry.hasReferences {
            suffixes.append("[ref]")
        }
        if let link = entry.link {
            suffixes.append("[link->\(link)]")
        }
        if suffixes.isEmpty {
            return label
        }
        return label + " " + suffixes.joined(separator: " ")
    }

    /// Formats description text for display.
    ///
    /// Missing descriptions remain `nil`. Positive maximum lengths truncate long descriptions; a
    /// maximum length of zero disables truncation because no positive display budget was configured.
    ///
    /// - Parameters:
    ///   - entry: The entry containing optional description text.
    ///   - config: Display configuration containing the maximum description length.
    /// - Returns: The description text to render, or `nil` when the entry has no description.
    private func descriptionText(for entry: TreeEntry, config: TreedocsConfig) -> String? {
        guard let description = entry.description else {
            return nil
        }

        let maxLength = max(config.resolvedMaxDescriptionLength, 0)
        guard maxLength > 0, description.count > maxLength else {
            return description
        }

        if maxLength <= 3 {
            return String(description.prefix(maxLength))
        }

        return String(description.prefix(maxLength - 3)) + "..."
    }
}
