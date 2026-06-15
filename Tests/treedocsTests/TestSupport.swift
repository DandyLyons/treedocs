import Foundation
import PathKit
@preconcurrency import Rainbow
@testable import treedocs

final class TestWorkspace {
    let root: Path
    private let fileManager = FileManager.default

    init() throws {
        let directory = fileManager.temporaryDirectory.appendingPathComponent("treedocs-tests-\(UUID().uuidString)")
        root = Path(directory.path)
        try fileManager.createDirectory(atPath: root.string, withIntermediateDirectories: true)
    }

    deinit {
        try? fileManager.removeItem(atPath: root.string)
    }

    func createDirectory(_ relativePath: String) throws {
        try fileManager.createDirectory(atPath: (root + Path(relativePath)).string, withIntermediateDirectories: true)
    }

    func writeFile(_ relativePath: String, contents: String = "") throws {
        let path = root + Path(relativePath)
        try fileManager.createDirectory(atPath: path.parent().string, withIntermediateDirectories: true)
        try contents.write(to: path.url, atomically: true, encoding: .utf8)
    }

    func remove(_ relativePath: String) throws {
        try fileManager.removeItem(atPath: (root + Path(relativePath)).string)
    }

    func service(globalConfigYAML: String? = nil) throws -> TreedocsService {
        let globalConfigPath: Path?
        if let globalConfigYAML {
            globalConfigPath = root + Path("global-config.yaml")
            try globalConfigYAML.write(to: globalConfigPath!.url, atomically: true, encoding: .utf8)
        } else {
            globalConfigPath = nil
        }

        return TreedocsService(configLoader: ConfigLoader(globalConfigPath: globalConfigPath))
    }

    func saveState(_ file: TreedocsFile) throws {
        try TreedocsFileStore().save(file, at: root + Path("treedocs.yaml"))
    }

    func loadState() throws -> TreedocsFile {
        try TreedocsFileStore().load(at: root + Path("treedocs.yaml"))
    }
}

final class StubMissingDescriptionCollector: MissingDescriptionCollector {
    let result: MissingDescriptionCollectionResult
    private(set) var requestedPaths: [String] = []

    init(result: MissingDescriptionCollectionResult) {
        self.result = result
    }

    func collectDescriptions(for paths: [String]) throws -> MissingDescriptionCollectionResult {
        requestedPaths = paths
        return result
    }
}

func withRainbowConsoleOutput<T>(_ operation: () throws -> T) rethrows -> T {
    let previousEnabled = Rainbow.enabled
    let previousOutputTarget = Rainbow.outputTarget
    Rainbow.enabled = true
    Rainbow.outputTarget = .console
    defer {
        Rainbow.enabled = previousEnabled
        Rainbow.outputTarget = previousOutputTarget
    }
    return try operation()
}
