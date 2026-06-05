import Foundation

/// Describes the result of resolving a `_link` from a documented tree entry.
///
/// Link resolution distinguishes entries without links, external URLs, successfully resolved internal
/// links, broken internal targets, and internal cycles. Chains include the starting path followed by
/// each internal target that was visited.
enum LinkResolution: Equatable {
    /// The entry does not exist or has no link metadata.
    case none

    /// The link points to an HTTP or HTTPS URL.
    case external(url: String)

    /// The link chain resolved to another tree entry.
    case resolved(path: String, chain: [String], entry: TreeEntry)

    /// The link chain pointed at a missing tree entry.
    case broken(target: String, chain: [String])

    /// The link chain revisited an internal target.
    case cycle(chain: [String])
}

/// Resolves links between documented tree entries.
///
/// `LinkResolver` follows internal `_link` targets using repository-relative path rules and stops at
/// the first external URL, missing target, cycle, or unlinked entry.
struct LinkResolver {
    /// Resolves the link chain for a documented path.
    ///
    /// Relative targets beginning with `./` or `../` are resolved from the entry that contains the
    /// link. HTTP and HTTPS targets are reported as external without further traversal.
    ///
    /// - Parameters:
    ///   - path: The documented path whose link should be resolved.
    ///   - tree: The tree containing the path and its possible targets.
    /// - Returns: A structured link resolution result.
    func resolve(path: String, in tree: [String: TreeEntry]) -> LinkResolution {
        guard let startingEntry = TreeOperations.entry(at: path, in: tree) else {
            return .none
        }
        guard let link = startingEntry.link else {
            return .none
        }

        if link.hasPrefix("http://") || link.hasPrefix("https://") {
            return .external(url: link)
        }

        var visited: Set<String> = [path]
        var chain = [path]
        var currentPath = RelativePath.resolve(link, from: path)

        while true {
            chain.append(currentPath)
            guard let entry = TreeOperations.entry(at: currentPath, in: tree) else {
                return .broken(target: currentPath, chain: chain)
            }

            if let nextLink = entry.link {
                if nextLink.hasPrefix("http://") || nextLink.hasPrefix("https://") {
                    return .external(url: nextLink)
                }
                if visited.contains(currentPath) {
                    return .cycle(chain: chain)
                }
                visited.insert(currentPath)
                currentPath = RelativePath.resolve(nextLink, from: currentPath)
                continue
            }

            return .resolved(path: currentPath, chain: chain, entry: entry)
        }
    }
}
