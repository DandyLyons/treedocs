import Foundation

/// Renders documented tree entries as human-readable text.
///
/// The renderer is responsible only for presentation. It does not resolve links or mutate entries;
/// it formats tree connectors, labels, optional reference/link markers, alignment, colors, and
/// truncated descriptions according to `TreedocsConfig`.
struct TreeRenderer {
    private struct RenderRow {
        var label: String
        var visibleLabelLength: Int
        var description: String?
    }

    enum EntryStatus {
        case clean
        case warning
        case error

        var ansiCode: String {
            switch self {
            case .clean: return "\u{001B}[1;32m"
            case .warning: return "\u{001B}[1;33m"
            case .error: return "\u{001B}[1;31m"
            }
        }
    }

    private let ansiReset = "\u{001B}[0m"

    /// Renders a tree or subtree.
    ///
    /// When `subtreePath` names a directory, that directory is rendered as the root of the tree. When
    /// it names a file, a single-file tree is rendered.
    ///
    /// - Parameters:
    ///   - tree: The full documentation tree to render from.
    ///   - subtreePath: An optional path limiting output to one subtree or file.
    ///   - config: Display configuration controlling indentation, alignment, and description length.
    /// - Returns: A newline-separated textual representation of the requested tree.
    /// - Throws: `TreeDocsError` when `subtreePath` does not exist in `tree`.
    func render(
        tree: [String: TreeEntry],
        subtreePath: String?,
        config: TreedocsConfig,
        statusOverrides: [String: EntryStatus] = [:]
    ) throws -> String {
        let rootLabel: String
        let rootEntry: TreeEntry?
        let renderedTree: [String: TreeEntry]

        if let subtreePath, let normalized = RelativePath.normalize(subtreePath).trimmedNilIfEmpty {
            guard let entry = TreeOperations.entry(at: normalized, in: tree) else {
                throw TreeDocsError.message("Path not found in treedocs tree: \(normalized)")
            }

            rootLabel = entry.isDirectory ? normalized + "/" : normalized
            rootEntry = entry
            renderedTree = entry.isDirectory ? entry.children : [:]
        } else {
            rootLabel = "."
            rootEntry = nil
            renderedTree = tree
        }

        let rootPath = subtreePath.map(RelativePath.normalize) ?? ""
        var flattened = [rootRow(label: rootLabel, entry: rootEntry, path: rootPath, config: config, statusOverrides: statusOverrides)]
        flattened.append(contentsOf: flattenForRender(tree: renderedTree, prefix: "", pathPrefix: rootPath, config: config, statusOverrides: statusOverrides))

        let labelWidth = config.resolvedAlignColumns ? flattened.map(\.visibleLabelLength).max() ?? 0 : 0
        let rendered = flattened.map { item in
            let padding = config.resolvedAlignColumns ? String(repeating: " ", count: max(labelWidth - item.visibleLabelLength, 0)) : ""
            let label = item.label + padding
            if let description = item.description {
                return "\(label)  \(description)"
            }
            return label
        }
        return rendered.joined(separator: "\n")
    }

    /// Builds the root row for a rendered tree.
    ///
    /// The synthetic `.` root is always shown as clean because repository-wide drift is reported
    /// separately by `show` and is not represented by a real tree entry.
    private func rootRow(label: String, entry: TreeEntry?, path: String, config: TreedocsConfig, statusOverrides: [String: EntryStatus]) -> RenderRow {
        let status = statusOverrides[path] ?? entry.map { entryStatus(for: $0, config: config) } ?? EntryStatus.clean
        let decorated = decorate(label: styled(label: label, status: status), entry: entry)
        let plain = decorate(label: label, entry: entry)
        return RenderRow(label: decorated, visibleLabelLength: plain.count, description: entry.map { descriptionText(for: $0, config: config) } ?? nil)
    }

    /// Flattens a nested tree into connector-based render rows.
    ///
    /// Each returned row contains a fully decorated label and the already-truncated description text,
    /// leaving column alignment to the top-level render method.
    ///
    /// - Parameters:
    ///   - tree: The tree or subtree to flatten.
    ///   - prefix: The visible tree prefix made from ancestor connectors.
    ///   - config: Display configuration for indentation and description length.
    /// - Returns: Ordered render rows containing labels and optional descriptions.
    private func flattenForRender(
        tree: [String: TreeEntry],
        prefix: String,
        pathPrefix: String,
        config: TreedocsConfig,
        statusOverrides: [String: EntryStatus]
    ) -> [RenderRow] {
        var lines: [RenderRow] = []
        let keys = tree.keys.sorted()

        for (index, key) in keys.enumerated() {
            guard let entry = tree[key] else { continue }
            let isLast = index == keys.count - 1
            let connector = isLast ? "└── " : "├── "
            let childPrefix = prefix + (isLast ? "    " : "│   ")
            let path = pathPrefix.isEmpty ? key : pathPrefix + "/" + key
            let marker = entry.isDirectory ? "\(key)/" : key
            let status = statusOverrides[path] ?? entryStatus(for: entry, config: config)
            let decorated = decorate(label: styled(label: marker, status: status), entry: entry)
            let plain = decorate(label: marker, entry: entry)
            lines.append(RenderRow(
                label: prefix + connector + decorated,
                visibleLabelLength: (prefix + connector + plain).count,
                description: descriptionText(for: entry, config: config)
            ))
            if entry.isDirectory {
                lines.append(contentsOf: flattenForRender(
                    tree: entry.children,
                    prefix: childPrefix,
                    pathPrefix: path,
                    config: config,
                    statusOverrides: statusOverrides
                ))
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
    private func decorate(label: String, entry: TreeEntry?) -> String {
        var suffixes: [String] = []
        if entry?.hasReferences == true {
            suffixes.append("[ref]")
        }
        if let link = entry?.link {
            suffixes.append("[link->\(link)]")
        }
        if suffixes.isEmpty {
            return label
        }
        return label + " " + suffixes.joined(separator: " ")
    }

    /// Determines the display status color for one entry.
    private func entryStatus(for entry: TreeEntry, config: TreedocsConfig) -> EntryStatus {
        guard entry.needsDescription else {
            return .clean
        }

        return config.resolvedCheckSeverity == .warn ? .warning : .error
    }

    /// Applies ANSI bold color styling to a path label.
    private func styled(label: String, status: EntryStatus) -> String {
        status.ansiCode + label + ansiReset
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
