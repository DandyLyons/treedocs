import Darwin
import Foundation

/// Evaluates repository paths against standard and configured ignore patterns.
///
/// The matcher combines hard-coded excludes for treedocs and build artifacts with user-provided
/// gitignore-style patterns. Later patterns can override earlier ones through `!` negation.
struct IgnoreMatcher {
    private let patterns: [String]
    private let standardExcludedNames: Set<String> = [
        ".git",
        ".build",
        ".swiftpm",
        ".treedocs",
        ".agents",
        ".opencode",
        "node_modules",
        "treedocs.yaml",
    ]

    /// Creates an ignore matcher.
    ///
    /// - Parameter patterns: Additional gitignore-style patterns to evaluate after standard excludes.
    init(patterns: [String]) {
        self.patterns = patterns
    }

    /// Determines whether a repository-relative path should be excluded.
    ///
    /// Standard excluded names always win. Configured patterns are then evaluated in order, with
    /// negated patterns clearing a previous ignore decision when they match.
    ///
    /// - Parameters:
    ///   - relativePath: The repository-relative path to test.
    ///   - isDirectory: Whether the path identifies a directory.
    /// - Returns: `true` when the scanner should skip the path.
    func shouldIgnore(relativePath: String, isDirectory: Bool) -> Bool {
        let normalized = RelativePath.normalize(relativePath)
        guard !normalized.isEmpty else {
            return false
        }

        let components = normalized.split(separator: "/").map(String.init)
        if components.contains(where: { standardExcludedNames.contains($0) }) {
            return true
        }

        var ignored = false
        for pattern in patterns {
            guard let rawPattern = pattern.trimmedNilIfEmpty else {
                continue
            }

            let isNegated = rawPattern.hasPrefix("!")
            let effectivePattern = isNegated ? String(rawPattern.dropFirst()) : rawPattern
            guard matches(pattern: effectivePattern, path: normalized, basename: components.last ?? "", isDirectory: isDirectory) else {
                continue
            }

            ignored = !isNegated
        }
        return ignored
    }

    /// Matches one ignore pattern against one normalized path.
    ///
    /// The implementation supports anchored patterns, directory-only patterns, basic `fnmatch`
    /// globbing, basename matches, and nested path matches.
    ///
    /// - Parameters:
    ///   - pattern: The raw pattern after removing any leading negation marker.
    ///   - path: The normalized repository-relative path.
    ///   - basename: The final component of `path`.
    ///   - isDirectory: Whether `path` identifies a directory.
    /// - Returns: `true` when the pattern matches the path.
    private func matches(pattern: String, path: String, basename: String, isDirectory: Bool) -> Bool {
        guard let rawPattern = pattern.trimmedNilIfEmpty else {
            return false
        }

        let directoryPattern = rawPattern.hasSuffix("/")
        let unwrapped = directoryPattern ? String(rawPattern.dropLast()) : rawPattern
        let anchored = unwrapped.hasPrefix("/")
        let normalizedPattern = anchored ? String(unwrapped.dropFirst()) : unwrapped

        if directoryPattern, !isDirectory, path == normalizedPattern {
            return false
        }

        if normalizedPattern.contains("*") || normalizedPattern.contains("?") {
            if fnmatch(normalizedPattern, path, 0) == 0 {
                return true
            }
            if !anchored && fnmatch(normalizedPattern, basename, 0) == 0 {
                return true
            }
        }

        if anchored {
            if path == normalizedPattern || path.hasPrefix(normalizedPattern + "/") {
                return true
            }
        } else if normalizedPattern.contains("/") {
            if path == normalizedPattern || path.hasPrefix(normalizedPattern + "/") || path.hasSuffix("/" + normalizedPattern) {
                return true
            }
        } else if basename == normalizedPattern || path.split(separator: "/").contains(where: { $0 == normalizedPattern }) {
            return true
        }

        return false
    }
}
