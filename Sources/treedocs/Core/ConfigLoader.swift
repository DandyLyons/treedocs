import Foundation
import PathKit
import Yams

/// Contains resolved configuration and active ignore patterns.
///
/// The configuration value reflects defaults merged with global config, project config, and state
/// overrides. Ignore patterns include configured excludes plus enabled ignore files.
struct LoadedConfiguration {
    /// The effective configuration after precedence rules have been applied.
    var config: TreedocsConfig

    /// The ordered ignore patterns used by the scanner.
    var ignorePatterns: [String]
}

/// Loads configuration for a repository.
///
/// Configuration precedence is defaults, then global config, then project config, then state
/// overrides. Ignore patterns are resolved alongside configuration so scanner callers do not need to
/// know where each pattern came from.
struct ConfigLoader {
    /// The optional global configuration path used before project-level config.
    var globalConfigPath: Path?

    /// Creates a configuration loader.
    ///
    /// Passing `nil` uses the default global config path under the user's home directory when one can
    /// be derived.
    ///
    /// - Parameter globalConfigPath: An explicit global config path, or `nil` to use the default.
    init(globalConfigPath: Path? = nil) {
        self.globalConfigPath = globalConfigPath ?? ConfigLoader.defaultGlobalConfigPath()
    }

    /// Resolves configuration and ignore patterns for a repository.
    ///
    /// The returned configuration applies all precedence layers. Ignore patterns include configured
    /// excludes, `.gitignore` when enabled, and `.treedocs/.treedocs_ignore`.
    ///
    /// - Parameters:
    ///   - root: The validated repository root path.
    ///   - stateOverrides: Optional overrides loaded from `treedocs.yaml`.
    /// - Returns: The effective configuration and ordered ignore pattern list.
    /// - Throws: `TreeDocsError` for invalid config shape or UTF-8 failures, and YAML parsing errors from Yams.
    func load(root: Path, stateOverrides: TreedocsConfig?) throws -> LoadedConfiguration {
        let repositoryPaths = RepositoryPaths(root: root)
        let globalConfig = try loadConfigIfExists(at: globalConfigPath)
        let projectConfig = try loadConfigIfExists(at: repositoryPaths.projectConfig)
        let resolved = TreedocsConfig.defaults
            .merging(globalConfig)
            .merging(projectConfig)
            .merging(stateOverrides)

        let ignorePatterns = resolved.resolvedExclude
            + (resolved.resolvedUseGitignore ? loadIgnoreFileIfExists(at: repositoryPaths.gitignore) : [])
            + loadIgnoreFileIfExists(at: repositoryPaths.projectIgnore)

        return LoadedConfiguration(config: resolved, ignorePatterns: ignorePatterns)
    }

    /// Loads a YAML configuration file when it exists.
    ///
    /// Missing files are treated as absent configuration. Empty YAML files also produce `nil` so they
    /// do not affect precedence merging.
    ///
    /// - Parameter path: The optional config path to read.
    /// - Returns: Parsed configuration, or `nil` when no usable config exists.
    /// - Throws: `TreeDocsError` for UTF-8 or schema errors, and YAML parsing errors from Yams.
    private func loadConfigIfExists(at path: Path?) throws -> TreedocsConfig? {
        guard let path, path.exists else {
            return nil
        }
        let rawData = try path.read()
        guard let raw = String(data: rawData, encoding: .utf8) else {
            throw TreeDocsError.message("Failed to decode config file at \(path.string) as UTF-8.")
        }
        guard let yaml = try Yams.load(yaml: raw) else {
            return nil
        }
        return try TreedocsConfig.fromYAML(yaml)
    }

    /// Loads ignore patterns from a file when it exists.
    ///
    /// Lines are trimmed, empty lines are skipped, and comment lines beginning with `#` are ignored.
    /// Read failures are treated as an empty pattern list so optional ignore files remain best effort.
    ///
    /// - Parameter path: The ignore file path to read.
    /// - Returns: The active ignore patterns from the file.
    private func loadIgnoreFileIfExists(at path: Path) -> [String] {
        guard path.exists, let rawData = try? path.read(), let contents = String(data: rawData, encoding: .utf8) else {
            return []
        }

        return contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Returns the conventional per-user configuration path.
    ///
    /// The path is derived from `HOME` when available, falling back to `NSHomeDirectory()`.
    ///
    /// - Returns: `$HOME/.config/treedocs/config.yaml`, or `nil` when no home directory is known.
    private static func defaultGlobalConfigPath() -> Path? {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        guard !home.isEmpty else {
            return nil
        }
        return Path(home) + Path(".config/treedocs/config.yaml")
    }
}

/// Adds an initializer for already-validated repository roots.
///
/// This extension is private to configuration loading because it intentionally skips the validation
/// performed by `RepositoryPaths.init(rootPath:)`.
private extension RepositoryPaths {
    /// Stores a pre-resolved repository root path.
    ///
    /// - Parameter root: A repository root that has already been validated by the caller.
    init(root: Path) {
        self.root = root
    }
}
