/// Result of an interactive missing-description collection session.
enum MissingDescriptionCollectionResult: Equatable {
    /// The user chose to save the supplied descriptions.
    case save([String: String])

    /// The user cancelled without saving any staged changes.
    case cancel
}

/// Collects descriptions for tree entries that still need documentation.
protocol MissingDescriptionCollector {
    /// Collect descriptions for the supplied missing-description candidates.
    ///
    /// - Parameter candidates: Relative tree paths that need descriptions, enriched with suggestions when available.
    /// - Returns: A save or cancel decision from the collection session.
    func collectDescriptions(for candidates: [MissingDescriptionCandidate]) throws -> MissingDescriptionCollectionResult
}
