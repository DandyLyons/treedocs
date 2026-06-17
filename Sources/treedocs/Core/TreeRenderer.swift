import Foundation
import Rainbow

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
    }

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

        return renderRows(flattened, config: config)
    }

    /// Renders the root tree with selected paths expanded one level.
    ///
    /// Exploration output is always rooted at `.`. The root's immediate children are shown, requested
    /// directories expand exactly one level, and ancestor directories are opened only far enough to
    /// make requested deeper paths reachable.
    ///
    /// - Parameters:
    ///   - tree: The full documentation tree to render from.
    ///   - expandedPaths: Paths to expand within the root tree. An empty list expands the root.
    ///   - config: Display configuration controlling indentation, alignment, and description length.
    ///   - statusOverrides: Optional status overrides for stale scanned paths.
    /// - Returns: A newline-separated textual representation of the explored tree.
    /// - Throws: `TreeDocsError` when a requested path does not exist in `tree`.
    func renderExploration(
        tree: [String: TreeEntry],
        expandedPaths: [String],
        config: TreedocsConfig,
        statusOverrides: [String: EntryStatus] = [:]
    ) throws -> String {
        let normalizedPaths = expandedPaths.isEmpty ? [""] : expandedPaths.map(RelativePath.normalize)
        let expandedPathSet = Set(normalizedPaths)

        for path in expandedPathSet {
            guard TreeOperations.entry(at: path, in: tree) != nil else {
                throw TreeDocsError.message("Path not found in treedocs tree: \(path)")
            }
        }

        var flattened = [RenderRow(
            label: "Expand collapsed folders with `treedocs explore <subpath>`.",
            visibleLabelLength: "Expand collapsed folders with `treedocs explore <subpath>`.".count,
            description: nil
        )]
        flattened.append(rootRow(label: ".", entry: nil, path: "", config: config, statusOverrides: statusOverrides))
        flattened.append(contentsOf: flattenForExploration(
            tree: tree,
            prefix: "",
            pathPrefix: "",
            expandedPaths: expandedPathSet,
            config: config,
            statusOverrides: statusOverrides
        ))

        return renderRows(flattened, config: config)
    }

    /// Applies optional column alignment and joins render rows.
    private func renderRows(_ rows: [RenderRow], config: TreedocsConfig) -> String {
        let labelWidth = config.resolvedAlignColumns ? rows.map(\.visibleLabelLength).max() ?? 0 : 0
        let rendered = rows.map { item in
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
        let styledLabel = switch status {
        case .clean: label.green.bold
        case .warning: label.yellow.bold
        case .error: label.red.bold
        }
        let decorated = decorate(label: styledLabel, entry: entry)
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
            let styledLabel = switch status {
            case .clean: marker.green.bold
            case .warning: marker.yellow.bold
            case .error: marker.red.bold
            }
            let decorated = decorate(label: styledLabel, entry: entry)
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

    /// Flattens a tree for progressive disclosure rendering.
    private func flattenForExploration(
        tree: [String: TreeEntry],
        prefix: String,
        pathPrefix: String,
        expandedPaths: Set<String>,
        config: TreedocsConfig,
        statusOverrides: [String: EntryStatus]
    ) -> [RenderRow] {
        var lines: [RenderRow] = []
        let keys = visibleExplorationKeys(in: tree, pathPrefix: pathPrefix, expandedPaths: expandedPaths)

        for (index, key) in keys.enumerated() {
            guard let entry = tree[key] else { continue }
            let isLast = index == keys.count - 1
            let connector = isLast ? "└── " : "├── "
            let childPrefix = prefix + (isLast ? "    " : "│   ")
            let path = pathPrefix.isEmpty ? key : pathPrefix + "/" + key
            let marker = entry.isDirectory ? "\(key)/" : key
            let status = statusOverrides[path] ?? entryStatus(for: entry, config: config)
            let styledLabel = switch status {
            case .clean: marker.green.bold
            case .warning: marker.yellow.bold
            case .error: marker.red.bold
            }
            var decorated = decorate(label: styledLabel, entry: entry)
            var plain = decorate(label: marker, entry: entry)
            let shouldDescend = entry.isDirectory && shouldDescendDuringExploration(path: path, expandedPaths: expandedPaths)
            if entry.isDirectory, !shouldDescend {
                let itemCount = collapsedItemCount(for: entry)
                decorated += " " + itemCount.lightBlack
                plain += " " + itemCount
            }
            lines.append(RenderRow(
                label: prefix + connector + decorated,
                visibleLabelLength: (prefix + connector + plain).count,
                description: descriptionText(for: entry, config: config)
            ))
            if shouldDescend {
                lines.append(contentsOf: flattenForExploration(
                    tree: entry.children,
                    prefix: childPrefix,
                    pathPrefix: path,
                    expandedPaths: expandedPaths,
                    config: config,
                    statusOverrides: statusOverrides
                ))
            }
        }

        return lines
    }

    /// Returns child keys visible under a directory in exploration mode.
    private func visibleExplorationKeys(in tree: [String: TreeEntry], pathPrefix: String, expandedPaths: Set<String>) -> [String] {
        let keys = tree.keys.sorted()
        if pathPrefix.isEmpty || expandedPaths.contains(pathPrefix) {
            return keys
        }

        return keys.filter { key in
            let childPath = pathPrefix + "/" + key
            return expandedPaths.contains(childPath) || expandedPaths.contains { $0.hasPrefix(childPath + "/") }
        }
    }

    /// Returns whether a directory should reveal children in exploration mode.
    private func shouldDescendDuringExploration(path: String, expandedPaths: Set<String>) -> Bool {
        expandedPaths.contains(path) || expandedPaths.contains { $0.hasPrefix(path + "/") }
    }

    /// Formats the collapsed child count for a directory.
    private func collapsedItemCount(for entry: TreeEntry) -> String {
        let itemCount = entry.children.count
        let itemLabel = itemCount == 1 ? "item" : "items"
        return "(\(itemCount) \(itemLabel))"
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
