import Darwin
import Foundation

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

    init(patterns: [String]) {
        self.patterns = patterns
    }

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
