import Foundation

struct TreeRenderer {
    func render(tree: [String: TreeEntry], subtreePath: String?, config: TreedocsConfig) throws -> String {
        let renderedTree: [String: TreeEntry]
        let pathPrefix: String

        if let subtreePath, let normalized = subtreePath.trimmedNilIfEmpty {
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
