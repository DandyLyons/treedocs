#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import PathKit

/// Contains a scanned documentation tree and its signature inputs.
///
/// `TreeScanResult` separates the tree used for YAML state from the normalized path list used to
/// produce stable drift signatures.
struct TreeScanResult {
    /// The tree generated from the filesystem scan.
    var tree: [String: TreeEntry]

    /// The normalized file and directory paths included in the signature payload.
    var normalizedPaths: [String]

    /// Child directories that contain their own `treedocs.yaml` state file.
    var nestedBoundaries: [String]

    /// The stable signature for `normalizedPaths`.
    var signature: String {
        TreeSignature.make(from: normalizedPaths)
    }
}

/// Calculates stable signatures for normalized repository tree paths.
///
/// Signatures intentionally ignore descriptions, references, and links so they represent filesystem
/// structure drift rather than documentation content changes.
enum TreeSignature {
    /// Creates a SHA-256 signature from normalized repository paths.
    ///
    /// Paths are sorted before hashing to keep signatures deterministic regardless of traversal order.
    ///
    /// - Parameter normalizedPaths: The file and directory paths included in the tree structure.
    /// - Returns: A `sha256:`-prefixed hexadecimal digest string.
    static func make(from normalizedPaths: [String]) -> String {
        let payload = normalizedPaths.sorted().joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}

/// Scans a repository into a documentation tree.
///
/// `TreeScanner` walks the filesystem, applies ignore rules, creates empty documentation entries for
/// discovered files and directories, and records normalized paths for signature generation.
struct TreeScanner {
    private let fileManager = FileManager.default

    /// Scans a repository root.
    ///
    /// - Parameters:
    ///   - root: The repository root to scan.
    ///   - ignoreMatcher: The matcher used to skip standard and configured excluded paths.
    /// - Returns: The scanned tree and normalized paths used for its signature.
    /// - Throws: Filesystem errors from enumerating directories.
    func scan(root: Path, ignoreMatcher: IgnoreMatcher) throws -> TreeScanResult {
        var nestedBoundaries: [String] = []
        let tree = try buildTree(root: root, relativePath: "", ignoreMatcher: ignoreMatcher, nestedBoundaries: &nestedBoundaries)
        var normalizedPaths: [String] = []
        TreeOperations.collectNormalizedPaths(in: tree, into: &normalizedPaths)
        return TreeScanResult(tree: tree, normalizedPaths: normalizedPaths, nestedBoundaries: nestedBoundaries.sorted())
    }

    /// Recursively scans children beneath a relative path.
    ///
    /// The returned dictionary is keyed by each child's basename. Directory entries contain recursively
    /// scanned children; file entries are leaves with empty descriptions.
    ///
    /// - Parameters:
    ///   - root: The repository root being scanned.
    ///   - relativePath: The directory path under `root` to scan, or an empty string for the root.
    ///   - ignoreMatcher: The matcher used to skip ignored paths.
    /// - Returns: Tree entries for the visible children under `relativePath`.
    /// - Throws: Filesystem errors from enumerating directories.
    private func buildTree(
        root: Path,
        relativePath: String,
        ignoreMatcher: IgnoreMatcher,
        nestedBoundaries: inout [String]
    ) throws -> [String: TreeEntry] {
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
                if containsNestedStateFile(at: childAbsolutePath) {
                    nestedBoundaries.append(childRelativePath)
                    result[childName] = TreeEntry(description: "", children: [:], isDirectory: true)
                    continue
                }

                let children = try buildTree(root: root, relativePath: childRelativePath, ignoreMatcher: ignoreMatcher, nestedBoundaries: &nestedBoundaries)
                result[childName] = TreeEntry(description: "", children: children, isDirectory: true)
            } else {
                result[childName] = TreeEntry(description: "")
            }
        }

        return result
    }

    /// Returns whether a scanned child directory owns its own documentation state.
    ///
    /// The repository root's state file is ignored by standard excludes before scanning begins, but a
    /// `treedocs.yaml` inside a child directory marks a delegated subtree boundary for the parent.
    private func containsNestedStateFile(at directory: Path) -> Bool {
        (directory + Path("treedocs.yaml")).isFile
    }
}
