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

    /// Prompts once per path and field with every distinct value from all participating sources.
    ///
    /// - Parameter conflicts: README/treedocs differences to resolve before any files are written.
    /// - Returns: Complete conflict winners or cancellation.
    func collectResolutions(for conflicts: [ReadmeMetadataConflict]) throws -> ReadmeConflictCollectionResult {
        var resolutions: [String: ReadmeConflictWinner] = [:]
        var remainingSource: ConflictSourcePreference?
        for conflict in conflicts {
            if let value = remainingSource?.value(in: conflict) {
                resolutions[conflict.id] = .value(value)
                continue
            }
            let choices = choices(for: conflict)

            let selected = noora.singleChoicePrompt(
                title: "README metadata conflict",
                question: TerminalText(stringLiteral: "\(conflict.targetPath) [\(conflict.field.rawValue)]"),
                options: choices,
                description: TerminalText(stringLiteral: conflict.diagnostic),
                collapseOnSelection: true,
                filterMode: .disabled,
                autoselectSingleChoice: false
            )

            switch selected.action {
            case let .keep(value):
                resolutions[conflict.id] = .value(value)
            case let .keepRemaining(preference, value):
                resolutions[conflict.id] = .value(value)
                remainingSource = preference
            case .cancel:
                return .cancel
            }
        }

        return .resolve(resolutions)
    }

    private func choices(for conflict: ReadmeMetadataConflict) -> [ReadmeConflictChoice] {
        var choices = conflict.values.map { value in
            var labels = conflict.readmeValues
                .filter { $0.value == value }
                .map(\.readmePath)
            if conflict.treedocsValue == value {
                labels.append("treedocs.yaml")
            }
            return ReadmeConflictChoice(
                action: .keep(value),
                description: "Keep \(value) (\(labels.joined(separator: ", ")))"
            )
        }

        if let treedocsValue = conflict.treedocsValue {
            choices.append(ReadmeConflictChoice(
                action: .keepRemaining(.treedocs, treedocsValue),
                description: "Keep treedocs for all remaining conflicts"
            ))
        }
        var seenReadmes = Set<String>()
        for source in conflict.readmeValues where seenReadmes.insert(source.readmePath).inserted {
            choices.append(ReadmeConflictChoice(
                action: .keepRemaining(.readme(source.readmePath), source.value),
                description: "Keep \(source.readmePath) for all remaining conflicts where it participates"
            ))
        }
        choices.append(ReadmeConflictChoice(action: .cancel, description: "Cancel (discard changes)"))
        return choices
    }
}

private enum ConflictSourcePreference: Equatable {
    case treedocs
    case readme(String)

    func value(in conflict: ReadmeMetadataConflict) -> ReadmeConflictValue? {
        switch self {
        case .treedocs:
            conflict.treedocsValue
        case let .readme(path):
            conflict.readmeValues.first(where: { $0.readmePath == path })?.value
        }
    }
}

private struct ReadmeConflictChoice: Equatable, CustomStringConvertible {
    enum Action: Equatable {
        case keep(ReadmeConflictValue)
        case keepRemaining(ConflictSourcePreference, ReadmeConflictValue)
        case cancel
    }

    let action: Action
    let description: String
}
