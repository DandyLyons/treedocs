/// Result of an interactive README conflict-resolution session.
enum ReadmeConflictCollectionResult: Equatable {
    /// Complete winners keyed by conflict identifier.
    case resolve([String: ReadmeConflictWinner])

    /// Abandon the entire staged sync without writing either source.
    case cancel
}

/// Collects one winner for every README/treedocs metadata conflict.
protocol ReadmeConflictCollector {
    /// Collects an authoritative source for every conflict or cancels the staged operation.
    ///
    /// - Parameter conflicts: Field conflicts in deterministic reconciliation order.
    /// - Returns: Complete resolutions or cancellation.
    /// - Throws: Errors produced by the interactive presentation layer.
    func collectResolutions(for conflicts: [ReadmeMetadataConflict]) throws -> ReadmeConflictCollectionResult
}
