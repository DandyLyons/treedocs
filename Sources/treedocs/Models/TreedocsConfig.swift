import Foundation

enum CheckSeverity: String {
    case error
    case warn
}

struct TreedocsConfig: Equatable {
    var exclude: [String]?
    var useGitignore: Bool?
    var maxDescriptionLength: Int?
    var indentSize: Int?
    var alignColumns: Bool?
    var checkSeverity: CheckSeverity?
    var autoInitEmpty: Bool?
    var theme: String?
    var icons: Bool?
    var aiProvider: String?
    var aiModel: String?

    init(
        exclude: [String]? = nil,
        useGitignore: Bool? = nil,
        maxDescriptionLength: Int? = nil,
        indentSize: Int? = nil,
        alignColumns: Bool? = nil,
        checkSeverity: CheckSeverity? = nil,
        autoInitEmpty: Bool? = nil,
        theme: String? = nil,
        icons: Bool? = nil,
        aiProvider: String? = nil,
        aiModel: String? = nil
    ) {
        self.exclude = exclude
        self.useGitignore = useGitignore
        self.maxDescriptionLength = maxDescriptionLength
        self.indentSize = indentSize
        self.alignColumns = alignColumns
        self.checkSeverity = checkSeverity
        self.autoInitEmpty = autoInitEmpty
        self.theme = theme
        self.icons = icons
        self.aiProvider = aiProvider
        self.aiModel = aiModel
    }

    static let defaults = TreedocsConfig(
        exclude: [],
        useGitignore: true,
        maxDescriptionLength: 120,
        indentSize: 2,
        alignColumns: false,
        checkSeverity: .error,
        autoInitEmpty: false,
        theme: nil,
        icons: false,
        aiProvider: nil,
        aiModel: nil
    )

    func merging(_ other: TreedocsConfig?) -> TreedocsConfig {
        guard let other else { return self }
        return TreedocsConfig(
            exclude: other.exclude ?? exclude,
            useGitignore: other.useGitignore ?? useGitignore,
            maxDescriptionLength: other.maxDescriptionLength ?? maxDescriptionLength,
            indentSize: other.indentSize ?? indentSize,
            alignColumns: other.alignColumns ?? alignColumns,
            checkSeverity: other.checkSeverity ?? checkSeverity,
            autoInitEmpty: other.autoInitEmpty ?? autoInitEmpty,
            theme: other.theme ?? theme,
            icons: other.icons ?? icons,
            aiProvider: other.aiProvider ?? aiProvider,
            aiModel: other.aiModel ?? aiModel
        )
    }

    static func fromYAML(_ value: Any?) throws -> TreedocsConfig? {
        guard let value else { return nil }
        guard let mapping = value as? [String: Any] else {
            throw TreeDocsError.message("Invalid treedocs config: expected a mapping.")
        }

        return TreedocsConfig(
            exclude: parseStringArray(mapping["exclude"]),
            useGitignore: parseBool(mapping["use_gitignore"]),
            maxDescriptionLength: parseInt(mapping["max_description_length"]),
            indentSize: parseInt(mapping["indent_size"]),
            alignColumns: parseBool(mapping["align_columns"]),
            checkSeverity: parseSeverity(mapping["check_severity"]),
            autoInitEmpty: parseBool(mapping["auto_init_empty"]),
            theme: parseString(mapping["theme"]),
            icons: parseBool(mapping["icons"]),
            aiProvider: parseString(mapping["ai_provider"]),
            aiModel: parseString(mapping["ai_model"])
        )
    }

    func toYAMLValue() -> [String: Any] {
        var mapping: [String: Any] = [:]

        if let exclude {
            mapping["exclude"] = exclude
        }
        if let useGitignore {
            mapping["use_gitignore"] = useGitignore
        }
        if let maxDescriptionLength {
            mapping["max_description_length"] = maxDescriptionLength
        }
        if let indentSize {
            mapping["indent_size"] = indentSize
        }
        if let alignColumns {
            mapping["align_columns"] = alignColumns
        }
        if let checkSeverity {
            mapping["check_severity"] = checkSeverity.rawValue
        }
        if let autoInitEmpty {
            mapping["auto_init_empty"] = autoInitEmpty
        }
        if let theme {
            mapping["theme"] = theme
        }
        if let icons {
            mapping["icons"] = icons
        }
        if let aiProvider {
            mapping["ai_provider"] = aiProvider
        }
        if let aiModel {
            mapping["ai_model"] = aiModel
        }

        return mapping
    }

    var resolvedExclude: [String] { exclude ?? [] }
    var resolvedUseGitignore: Bool { useGitignore ?? true }
    var resolvedMaxDescriptionLength: Int { maxDescriptionLength ?? 120 }
    var resolvedIndentSize: Int { indentSize ?? 2 }
    var resolvedAlignColumns: Bool { alignColumns ?? false }
    var resolvedCheckSeverity: CheckSeverity { checkSeverity ?? .error }
    var resolvedAutoInitEmpty: Bool { autoInitEmpty ?? false }
    var resolvedTheme: String? { theme }
    var resolvedIcons: Bool { icons ?? false }
}

func parseString(_ value: Any?) -> String? {
    switch value {
    case let string as String:
        return string
    case let number as NSNumber:
        return number.stringValue
    default:
        return nil
    }
}

func parseBool(_ value: Any?) -> Bool? {
    switch value {
    case let bool as Bool:
        return bool
    case let number as NSNumber:
        return number.boolValue
    case let string as String:
        switch string.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    default:
        return nil
    }
}

func parseInt(_ value: Any?) -> Int? {
    switch value {
    case let int as Int:
        return int
    case let number as NSNumber:
        return number.intValue
    case let string as String:
        return Int(string)
    default:
        return nil
    }
}

func parseStringArray(_ value: Any?) -> [String]? {
    switch value {
    case let values as [String]:
        return values
    case let values as [Any]:
        return values.compactMap(parseString)
    default:
        return nil
    }
}

func parseSeverity(_ value: Any?) -> CheckSeverity? {
    guard let raw = parseString(value)?.lowercased() else {
        return nil
    }
    return CheckSeverity(rawValue: raw)
}
