/// Result of an interactive missing-description collection session.
enum MissingDescriptionCollectionResult: Equatable {
    /// The user chose to save the supplied descriptions.
    case save([String: String])

    /// The user cancelled without saving any staged changes.
    case cancel
}

/// Collects descriptions for tree entries that still need documentation.
protocol MissingDescriptionCollector {
    /// Collect descriptions for the supplied missing-description paths.
    ///
    /// - Parameter paths: Relative tree paths that need descriptions.
    /// - Returns: A save or cancel decision from the collection session.
    func collectDescriptions(for paths: [String]) throws -> MissingDescriptionCollectionResult
}
