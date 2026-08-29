import Noora

/// Noora-backed field-by-field README conflict resolver.
struct NooraReadmeConflictCollector: ReadmeConflictCollector {
    private let noora: Noorable

    /// Creates a collector backed by the supplied Noora presenter.
    ///
    /// - Parameter noora: Prompt presenter, injectable for alternate terminal environments.
    init(noora: Noorable = Noora()) {
        self.noora = noora
    }

    /// Prompts field by field, with options to apply either source to all remaining conflicts.
    ///
    /// - Parameter conflicts: README/treedocs differences to resolve before any files are written.
    /// - Returns: Complete conflict winners or cancellation.
    func collectResolutions(for conflicts: [ReadmeMetadataConflict]) throws -> ReadmeConflictCollectionResult {
        var resolutions: [String: ReadmeConflictWinner] = [:]
        var defaultWinner: ReadmeConflictWinner?

        for conflict in conflicts {
            if let defaultWinner {
                resolutions[conflict.id] = defaultWinner
                continue
            }

            let selected = noora.singleChoicePrompt(
                title: "README metadata conflict",
                question: TerminalText(stringLiteral: "\(conflict.targetPath) [\(conflict.field.rawValue)]"),
                options: ReadmeConflictChoice.all,
                description: TerminalText(
                    stringLiteral: "README: \(conflict.readmeValue)\ntreedocs: \(conflict.treedocsValue)"
                ),
                collapseOnSelection: true,
                filterMode: .disabled,
                autoselectSingleChoice: false
            )

            switch selected.action {
            case let .keep(winner):
                resolutions[conflict.id] = winner
            case let .keepRemaining(winner):
                resolutions[conflict.id] = winner
                defaultWinner = winner
            case .cancel:
                return .cancel
            }
        }

        return .resolve(resolutions)
    }
}

private struct ReadmeConflictChoice: Equatable, CustomStringConvertible {
    enum Action: Equatable {
        case keep(ReadmeConflictWinner)
        case keepRemaining(ReadmeConflictWinner)
        case cancel
    }

    let action: Action
    let description: String

    static let all = [
        ReadmeConflictChoice(action: .keep(.readme), description: "Keep README"),
        ReadmeConflictChoice(action: .keep(.treedocs), description: "Keep treedocs"),
        ReadmeConflictChoice(action: .keepRemaining(.readme), description: "Keep README for all remaining conflicts"),
        ReadmeConflictChoice(action: .keepRemaining(.treedocs), description: "Keep treedocs for all remaining conflicts"),
        ReadmeConflictChoice(action: .cancel, description: "Cancel (discard changes)"),
    ]
}
