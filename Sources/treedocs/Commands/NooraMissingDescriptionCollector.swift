import Noora

/// Noora-backed collector for missing tree entry descriptions.
struct NooraMissingDescriptionCollector: MissingDescriptionCollector {
    private let noora: Noorable

    init(noora: Noorable = Noora()) {
        self.noora = noora
    }

    func collectDescriptions(for candidates: [MissingDescriptionCandidate]) throws -> MissingDescriptionCollectionResult {
        guard !candidates.isEmpty else {
            return .save([:])
        }

        var drafts: [String: String] = [:]
        while true {
            let options = candidates.map { candidate in
                MissingDescriptionChoice.path(
                    candidate.displayPath,
                    actionPath: candidate.path,
                    hasDraft: drafts[candidate.path]?.trimmedNilIfEmpty != nil,
                    hasSuggestion: candidate.suggestedDescription?.trimmedNilIfEmpty != nil
                )
            } + [
                .save(count: drafts.values.compactMap(\.trimmedNilIfEmpty).count),
                .cancel,
            ]

            let progressDescription = "\(drafts.values.compactMap(\.trimmedNilIfEmpty).count) of \(candidates.count) descriptions entered."
            let selected = noora.singleChoicePrompt(
                title: "Missing descriptions",
                question: "Choose a path to document, then save when ready.",
                options: options,
                description: TerminalText(stringLiteral: progressDescription),
                collapseOnSelection: true,
                filterMode: .disabled,
                autoselectSingleChoice: false
            )

            switch selected.action {
            case let .edit(path):
                guard let candidate = candidates.first(where: { $0.path == path }) else {
                    continue
                }
                drafts[path] = collectDescription(for: candidate, currentDraft: drafts[path])
            case .save:
                return .save(drafts)
            case .cancel:
                return .cancel
            }
        }
    }

    private func collectDescription(for candidate: MissingDescriptionCandidate, currentDraft: String?) -> String {
        guard let suggestion = candidate.suggestedDescription?.trimmedNilIfEmpty else {
            return customDescriptionPrompt(for: candidate.displayPath, defaultValue: currentDraft)
        }

        let selected = noora.singleChoicePrompt(
            title: "Description suggestion",
            question: TerminalText(stringLiteral: candidate.displayPath),
            options: [
                SuggestedDescriptionChoice.accept(suggestion),
                .custom,
                .blank,
            ],
            description: TerminalText(stringLiteral: suggestion),
            collapseOnSelection: true,
            filterMode: .disabled,
            autoselectSingleChoice: false
        )

        switch selected.action {
        case let .accept(description):
            return description
        case .custom:
            return customDescriptionPrompt(for: candidate.displayPath, defaultValue: currentDraft ?? suggestion)
        case .blank:
            return ""
        }
    }

    private func customDescriptionPrompt(for path: String, defaultValue: String?) -> String {
        noora.textPrompt(
            title: "Description",
            prompt: TerminalText(stringLiteral: path),
            description: "Blank descriptions are skipped when saving.",
            defaultValue: defaultValue,
            collapseOnAnswer: true,
            validationRules: []
        )
    }
}

private struct MissingDescriptionChoice: Equatable, CustomStringConvertible {
    enum Action: Equatable {
        case edit(String)
        case save
        case cancel
    }

    let action: Action
    private let label: String

    static func path(_ path: String, actionPath: String, hasDraft: Bool, hasSuggestion: Bool) -> MissingDescriptionChoice {
        let suffix = hasSuggestion ? " (suggested)" : ""
        return MissingDescriptionChoice(action: .edit(actionPath), label: "[\(hasDraft ? "x" : " ")] \(path)\(suffix)")
    }

    static func save(count: Int) -> MissingDescriptionChoice {
        MissingDescriptionChoice(action: .save, label: "Save (\(count) description\(count == 1 ? "" : "s"))")
    }

    static let cancel = MissingDescriptionChoice(action: .cancel, label: "Cancel (discard changes)")

    var description: String {
        label
    }
}

private struct SuggestedDescriptionChoice: Equatable, CustomStringConvertible {
    enum Action: Equatable {
        case accept(String)
        case custom
        case blank
    }

    let action: Action
    private let label: String

    static func accept(_ description: String) -> SuggestedDescriptionChoice {
        SuggestedDescriptionChoice(action: .accept(description), label: "Use suggested description")
    }

    static let custom = SuggestedDescriptionChoice(action: .custom, label: "Write custom description")
    static let blank = SuggestedDescriptionChoice(action: .blank, label: "Leave blank")

    var description: String {
        label
    }
}
