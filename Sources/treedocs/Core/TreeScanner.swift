import CryptoKit
import Foundation
import PathKit

struct TreeScanResult {
    var tree: [String: TreeEntry]
    var normalizedPaths: [String]

    var signature: String {
        TreeSignature.make(from: normalizedPaths)
    }
}

enum TreeSignature {
    static func make(from normalizedPaths: [String]) -> String {
        let payload = normalizedPaths.sorted().joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}

struct TreeScanner {
    private let fileManager = FileManager.default

    func scan(root: Path, ignoreMatcher: IgnoreMatcher) throws -> TreeScanResult {
        let tree = try buildTree(root: root, relativePath: "", ignoreMatcher: ignoreMatcher)
        var normalizedPaths: [String] = []
        TreeOperations.collectNormalizedPaths(in: tree, into: &normalizedPaths)
        return TreeScanResult(tree: tree, normalizedPaths: normalizedPaths)
    }

    private func buildTree(root: Path, relativePath: String, ignoreMatcher: IgnoreMatcher) throws -> [String: TreeEntry] {
        let absolutePath = relativePath.isEmpty ? root : root + Path(relativePath)
        let childNames = try fileManager.contentsOfDirectory(atPath: absolutePath.string).sorted()
        var result: [String: TreeEntry] = [:]

        for childName in childNames {
            let childRelativePath = relativePath.isEmpty ? childName : relativePath + "/" + childName
            let childAbsolutePath = root + Path(childRelativePath)
            let isDirectory = childAbsolutePath.isDirectory

            if ignoreMatcher.shouldIgnore(relativePath: childRelativePath, isDirectory: isDirectory) {
                continue
            }

            if isDirectory {
                let children = try buildTree(root: root, relativePath: childRelativePath, ignoreMatcher: ignoreMatcher)
                result[childName] = TreeEntry(description: "", children: children, isDirectory: true)
            } else {
                result[childName] = TreeEntry(description: "")
            }
        }

        return result
    }
}
