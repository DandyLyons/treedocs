import Foundation

enum LinkResolution: Equatable {
    case none
    case external(url: String)
    case resolved(path: String, chain: [String], entry: TreeEntry)
    case broken(target: String, chain: [String])
    case cycle(chain: [String])
}

struct LinkResolver {
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
