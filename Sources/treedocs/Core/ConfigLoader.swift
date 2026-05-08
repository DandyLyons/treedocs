import Foundation
import PathKit
import Yams

struct LoadedConfiguration {
    var config: TreedocsConfig
    var ignorePatterns: [String]
}

struct ConfigLoader {
    var globalConfigPath: Path?

    init(globalConfigPath: Path? = nil) {
        self.globalConfigPath = globalConfigPath ?? ConfigLoader.defaultGlobalConfigPath()
    }

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

    private static func defaultGlobalConfigPath() -> Path? {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        guard !home.isEmpty else {
            return nil
        }
        return Path(home) + Path(".config/treedocs/config.yaml")
    }
}

private extension RepositoryPaths {
    init(root: Path) {
        self.root = root
    }
}
