/// Result of an interactive README conflict-resolution session.
enum ReadmeConflictCollectionResult: Equatable {
    case resolve([String: ReadmeConflictWinner])
    case cancel
}

/// Collects one winner for every README/treedocs metadata conflict.
protocol ReadmeConflictCollector {
    func collectResolutions(for conflicts: [ReadmeMetadataConflict]) throws -> ReadmeConflictCollectionResult
}
