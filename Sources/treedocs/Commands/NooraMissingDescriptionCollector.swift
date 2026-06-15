import Noora

/// Noora-backed collector for missing tree entry descriptions.
struct NooraMissingDescriptionCollector: MissingDescriptionCollector {
    private let noora: Noorable

    init(noora: Noorable = Noora()) {
        self.noora = noora
    }

    func collectDescriptions(for paths: [String]) throws -> MissingDescriptionCollectionResult {
        guard !paths.isEmpty else {
            return .save([:])
        }

        var drafts: [String: String] = [:]
        while true {
            let options = paths.map { path in
                MissingDescriptionChoice.path(path, hasDraft: drafts[path]?.trimmedNilIfEmpty != nil)
            } + [
                .save(count: drafts.values.compactMap(\.trimmedNilIfEmpty).count),
                .cancel,
            ]

            let progressDescription = "\(drafts.values.compactMap(\.trimmedNilIfEmpty).count) of \(paths.count) descriptions entered."
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
                let answer = noora.textPrompt(
                    title: "Description",
                    prompt: TerminalText(stringLiteral: path),
                    description: "Blank descriptions are skipped when saving.",
                    defaultValue: drafts[path],
                    collapseOnAnswer: true,
                    validationRules: []
                )
                drafts[path] = answer
            case .save:
                return .save(drafts)
            case .cancel:
                return .cancel
            }
        }
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

    static func path(_ path: String, hasDraft: Bool) -> MissingDescriptionChoice {
        MissingDescriptionChoice(action: .edit(path), label: "[\(hasDraft ? "x" : " ")] \(path)")
    }

    static func save(count: Int) -> MissingDescriptionChoice {
        MissingDescriptionChoice(action: .save, label: "Save (\(count) description\(count == 1 ? "" : "s"))")
    }

    static let cancel = MissingDescriptionChoice(action: .cancel, label: "Cancel (discard changes)")

    var description: String {
        label
    }
}
