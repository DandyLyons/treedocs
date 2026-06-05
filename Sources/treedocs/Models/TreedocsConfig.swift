import Foundation

/// Controls how `treedocs check` reports validation issues.
///
/// Severity is loaded from configuration and determines whether detected drift or missing
/// descriptions should fail the command or only be printed as warnings.
enum CheckSeverity: String {
    /// Validation issues should fail the check command.
    case error

    /// Validation issues should be reported without failing the check command.
    case warn
}

/// Stores treedocs configuration values.
///
/// Every property is optional so configuration layers can be merged without losing the distinction
/// between an omitted value and an explicit override. Use resolved properties when a concrete value is
/// needed for runtime behavior.
struct TreedocsConfig: Equatable {
    /// Additional ignore patterns for the scanner.
    var exclude: [String]?

    /// Whether `.gitignore` should contribute ignore patterns.
    var useGitignore: Bool?

    /// Maximum rendered description length before truncation.
    var maxDescriptionLength: Int?

    /// Number of spaces used for each rendered tree indentation level.
    var indentSize: Int?

    /// Whether rendered labels should be padded into aligned columns.
    var alignColumns: Bool?

    /// The configured severity for `treedocs check`.
    var checkSeverity: CheckSeverity?

    /// Whether future automatic initialization behavior should create empty state.
    var autoInitEmpty: Bool?

    /// Optional theme name reserved for display customization.
    var theme: String?

    /// Whether icon rendering is enabled.
    var icons: Bool?

    /// Optional AI provider identifier for prompt-related workflows.
    var aiProvider: String?

    /// Optional AI model identifier for prompt-related workflows.
    var aiModel: String?

    /// Creates a configuration object.
    ///
    /// Pass `nil` for values that should not override earlier configuration layers.
    ///
    /// - Parameters:
    ///   - exclude: Additional ignore patterns for the scanner.
    ///   - useGitignore: Whether `.gitignore` should be loaded.
    ///   - maxDescriptionLength: Maximum rendered description length.
    ///   - indentSize: Number of spaces per rendered indentation level.
    ///   - alignColumns: Whether rendered labels should be column-aligned.
    ///   - checkSeverity: Severity used by `treedocs check`.
    ///   - autoInitEmpty: Reserved automatic initialization option.
    ///   - theme: Optional display theme name.
    ///   - icons: Whether icon rendering is enabled.
    ///   - aiProvider: Optional AI provider identifier.
    ///   - aiModel: Optional AI model identifier.
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

    /// The baseline configuration used before user-provided layers are merged.
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

    /// Merges another configuration over this one.
    ///
    /// Only non-`nil` values from `other` replace values in the receiver. This makes the method
    /// suitable for applying configuration precedence layers in order.
    ///
    /// - Parameter other: The higher-precedence configuration layer, or `nil` to keep this value.
    /// - Returns: A configuration containing values from this instance overridden by non-`nil` values from `other`.
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

    /// Parses treedocs configuration from YAML.
    ///
    /// Missing configuration returns `nil`. Present configuration must be a mapping whose keys match
    /// the snake_case schema names used in `treedocs.yaml` and `.treedocs/config.yaml`.
    ///
    /// - Parameter value: The raw YAML value to parse.
    /// - Returns: Parsed configuration, or `nil` when no configuration was provided.
    /// - Throws: `TreeDocsError` when the YAML value is present but not a mapping.
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

    /// Converts configuration to YAML.
    ///
    /// Only non-`nil` values are emitted so the resulting mapping represents explicit overrides, not
    /// resolved defaults.
    ///
    /// - Returns: A YAML-compatible mapping containing explicit configuration values.
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

    /// The resolved scanner exclude list.
    var resolvedExclude: [String] { exclude ?? [] }

    /// The resolved `.gitignore` loading setting.
    var resolvedUseGitignore: Bool { useGitignore ?? true }

    /// The resolved maximum description length for rendering.
    var resolvedMaxDescriptionLength: Int { maxDescriptionLength ?? 120 }

    /// The resolved indentation width for rendering.
    var resolvedIndentSize: Int { indentSize ?? 2 }

    /// The resolved column alignment setting for rendering.
    var resolvedAlignColumns: Bool { alignColumns ?? false }

    /// The resolved check severity.
    var resolvedCheckSeverity: CheckSeverity { checkSeverity ?? .error }

    /// The resolved automatic empty initialization setting.
    var resolvedAutoInitEmpty: Bool { autoInitEmpty ?? false }

    /// The resolved display theme name.
    var resolvedTheme: String? { theme }

    /// The resolved icon rendering setting.
    var resolvedIcons: Bool { icons ?? false }
}

/// Parses a YAML value into a string.
///
/// Strings are returned unchanged and `NSNumber` values are converted with `stringValue`. Unsupported
/// values are treated as absent.
///
/// - Parameter value: The raw YAML value to parse.
/// - Returns: A string representation, or `nil` when the value is unsupported.
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

/// Parses a YAML value into a Boolean.
///
/// Native Booleans and numbers are accepted. String values accept common true/false spellings used in
/// configuration files.
///
/// - Parameter value: The raw YAML value to parse.
/// - Returns: A Boolean value, or `nil` when the value is unsupported or unrecognized.
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

/// Parses a YAML value into an integer.
///
/// Native integers, numeric values, and decimal integer strings are accepted.
///
/// - Parameter value: The raw YAML value to parse.
/// - Returns: An integer value, or `nil` when the value is unsupported or cannot be converted.
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

/// Parses a YAML value into a string array.
///
/// String arrays are returned unchanged. Heterogeneous arrays are compact-mapped through
/// `parseString(_:)`, dropping unsupported elements.
///
/// - Parameter value: The raw YAML value to parse.
/// - Returns: A string array, or `nil` when the value is not an array.
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

/// Parses a YAML value into a check severity.
///
/// String-like values are lowercased before matching `CheckSeverity` raw values.
///
/// - Parameter value: The raw YAML value to parse.
/// - Returns: A check severity, or `nil` when the value is missing or unrecognized.
func parseSeverity(_ value: Any?) -> CheckSeverity? {
    guard let raw = parseString(value)?.lowercased() else {
        return nil
    }
    return CheckSeverity(rawValue: raw)
}
