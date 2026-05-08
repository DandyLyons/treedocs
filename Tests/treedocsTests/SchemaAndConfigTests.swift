import Foundation
import Testing
import PathKit
import Yams
@testable import treedocs

@Suite("Schema and Config")
struct SchemaAndConfigTests {
    @Test("YAML schema round-trips strings, objects, nested folders, links, and references")
    func schemaRoundTrip() throws {
        let yaml = """
        project:
          name: Example
        overrides:
          check_severity: warn
        signature: sha256:test
        tree:
          src:
            _doc: Main source
            api:
              _doc:
                description: REST API
                references:
                  - DOCS/API.md
              auth.swift: Handles auth
          docs:
            architecture:
              _doc: Alias folder
              _link: src/api
          README.md:
            description: Project entry point
            references:
              - https://example.com
        """

        let parsed = try TreedocsFile.load(from: yaml)
        #expect(parsed.signature == "sha256:test")
        #expect(parsed.overrides?.checkSeverity == .warn)
        #expect(TreeOperations.entry(at: "src", in: parsed.tree)?.description == "Main source")
        #expect(TreeOperations.entry(at: "src/api", in: parsed.tree)?.references == ["DOCS/API.md"])
        #expect(TreeOperations.entry(at: "docs/architecture", in: parsed.tree)?.link == "src/api")

        let roundTrip = try TreedocsFile.load(from: parsed.toYAMLString())
        #expect(roundTrip == parsed)
    }

    @Test("Config precedence applies defaults, global config, project config, and state overrides")
    func configPrecedence() throws {
        let workspace = try TestWorkspace()
        try workspace.createDirectory(".treedocs")
        try workspace.writeFile(".treedocs/config.yaml", contents: """
        exclude:
          - project-only
        align_columns: true
        indent_size: 4
        """)
        try workspace.writeFile(".treedocs/.treedocs_ignore", contents: """
        ignored-local
        """)
        try workspace.writeFile(".gitignore", contents: """
        ignored-from-git
        """)

        let loader = ConfigLoader(globalConfigPath: workspace.root + Path("global-config.yaml"))
        try workspace.writeFile("global-config.yaml", contents: """
        exclude:
          - global-only
        use_gitignore: true
        max_description_length: 80
        """)

        let loaded = try loader.load(
            root: workspace.root,
            stateOverrides: TreedocsConfig(
                exclude: nil,
                useGitignore: nil,
                maxDescriptionLength: nil,
                indentSize: 8,
                alignColumns: nil,
                checkSeverity: .warn,
                autoInitEmpty: nil,
                theme: nil,
                icons: nil,
                aiProvider: nil,
                aiModel: nil
            )
        )

        #expect(loaded.config.resolvedExclude == ["project-only"])
        #expect(loaded.config.resolvedUseGitignore)
        #expect(loaded.config.resolvedMaxDescriptionLength == 80)
        #expect(loaded.config.resolvedIndentSize == 8)
        #expect(loaded.config.resolvedAlignColumns)
        #expect(loaded.config.resolvedCheckSeverity == .warn)
        #expect(loaded.ignorePatterns.contains("project-only"))
        #expect(loaded.ignorePatterns.contains("ignored-from-git"))
        #expect(loaded.ignorePatterns.contains("ignored-local"))
    }

    @Test("Empty YAML produces a default TreedocsFile")
    func emptyYAML() throws {
        let file = try TreedocsFile.load(from: "")
        #expect(file.project.isEmpty)
        #expect(file.overrides == nil)
        #expect(file.signature == nil)
        #expect(file.tree.isEmpty)
    }

    @Test("YAML with only project section parses correctly")
    func partialYAMLProjectOnly() throws {
        let yaml = """
        project:
          name: Test
          version: "1.0"
        """
        let file = try TreedocsFile.load(from: yaml)
        #expect(file.project["name"] == "Test")
        #expect(file.project["version"] == "1.0")
        #expect(file.tree.isEmpty)
    }

    @Test("YAML with only signature parses correctly")
    func partialYAMLSignatureOnly() throws {
        let yaml = "signature: sha256:abc123\n"
        let file = try TreedocsFile.load(from: yaml)
        #expect(file.signature == "sha256:abc123")
        #expect(file.tree.isEmpty)
    }

    @Test("TreedocsFile default initializer produces empty state")
    func defaultTreedocsFile() {
        let file = TreedocsFile()
        #expect(file.project.isEmpty)
        #expect(file.overrides == nil)
        #expect(file.signature == nil)
        #expect(file.tree.isEmpty)
    }

    @Test("EntryDocumentation round-trips as simple string")
    func entryDocumentationStringRoundTrip() {
        let doc = EntryDocumentation(description: "Hello world")
        #expect(doc.toYAMLValue() as? String == "Hello world")
        #expect(!doc.isEmpty)
    }

    @Test("EntryDocumentation round-trips as mapping with references")
    func entryDocumentationMappingRoundTrip() {
        let doc = EntryDocumentation(description: "Hello", references: ["ref1", "ref2"])
        let value = doc.toYAMLValue() as? [String: Any]
        #expect(value != nil)
        #expect(value?["description"] as? String == "Hello")
        #expect(value?["references"] as? [String] == ["ref1", "ref2"])
    }

    @Test("EntryDocumentation with only references round-trips")
    func entryDocumentationReferencesOnly() {
        let doc = EntryDocumentation(references: ["ref1"])
        let value = doc.toYAMLValue() as? [String: Any]
        #expect(value?["description"] == nil)
        #expect(value?["references"] as? [String] == ["ref1"])
    }

    @Test("EntryDocumentation isEmpty for nil description and no references")
    func entryDocumentationEmptyCheck() {
        let doc = EntryDocumentation()
        #expect(doc.isEmpty)

        let docWithDescription = EntryDocumentation(description: "text")
        #expect(!docWithDescription.isEmpty)

        let docWithRefs = EntryDocumentation(references: ["r"])
        #expect(!docWithRefs.isEmpty)
    }

    @Test("EntryDocumentation fromYAML parses string")
    func entryDocumentationFromString() throws {
        let doc = try EntryDocumentation.fromYAML("Some description")
        #expect(doc?.description == "Some description")
        #expect(doc?.references.isEmpty == true)
    }

    @Test("EntryDocumentation fromYAML parses mapping")
    func entryDocumentationFromMapping() throws {
        let yaml = """
        description: API docs
        references:
          - docs/api.md
        """
        let parsed = try Yams.load(yaml: yaml)
        let doc = try EntryDocumentation.fromYAML(parsed)
        #expect(doc?.description == "API docs")
        #expect(doc?.references == ["docs/api.md"])
    }

    @Test("EntryDocumentation fromYAML returns nil for nil input")
    func entryDocumentationNilInput() throws {
        let doc = try EntryDocumentation.fromYAML(nil)
        #expect(doc == nil)
    }

    @Test("TreeEntry as simple string leaf")
    func treeEntryStringLeaf() throws {
        let entry = try TreeEntry.fromYAML("Simple description")
        #expect(entry.description == "Simple description")
        #expect(!entry.isDirectory)
        #expect(entry.children.isEmpty)
    }

    @Test("TreeEntry as mapping with description")
    func treeEntryMappingWithDescription() throws {
        let yaml = """
        description: A file
        _link: somewhere
        """
        let parsed = try Yams.load(yaml: yaml)
        let entry = try TreeEntry.fromYAML(parsed as Any)
        #expect(entry.description == "A file")
        #expect(entry.link == "somewhere")
        #expect(!entry.isDirectory)
    }

    @Test("TreeEntry as directory with children")
    func treeEntryDirectory() throws {
        let yaml = """
        subdir:
          file.txt: A nested file
        _doc: Directory docs
        """
        let parsed = try Yams.load(yaml: yaml)
        let entry = try TreeEntry.fromYAML(parsed as Any)
        #expect(entry.isDirectory)
        #expect(entry.description == "Directory docs")
        #expect(entry.children["subdir"] != nil)
    }

    @Test("TreeEntry toYAMLValue for leaf with description")
    func treeEntryToYAMLLeaf() {
        let entry = TreeEntry(description: "Leaf file")
        let value = entry.toYAMLValue()
        #expect(value as? String == "Leaf file")
    }

    @Test("TreeEntry toYAMLValue for leaf with link")
    func treeEntryToYAMLLeafWithLink() {
        let entry = TreeEntry(description: "Leaf", link: "target")
        let value = entry.toYAMLValue() as? [String: Any]
        #expect(value?["description"] as? String == "Leaf")
        #expect(value?["_link"] as? String == "target")
    }

    @Test("TreeEntry toYAMLValue for directory")
    func treeEntryToYAMLDirectory() {
        let entry = TreeEntry(
            documentation: EntryDocumentation(description: "Dir docs"),
            link: "target",
            children: ["file.swift": TreeEntry(description: "A swift file")],
            isDirectory: true
        )
        let value = entry.toYAMLValue() as? [String: Any]
        #expect(value?["_doc"] != nil)
        #expect(value?["_link"] as? String == "target")
        #expect(value?["file.swift"] != nil)
    }

    @Test("TreedocsConfig toYAMLValue omits nil fields")
    func configToYAMLOmitsNil() {
        let config = TreedocsConfig(indentSize: 4, theme: "dark")
        let value = config.toYAMLValue()
        #expect(value["indent_size"] as? Int == 4)
        #expect(value["theme"] as? String == "dark")
        #expect(value["exclude"] == nil)
        #expect(value["use_gitignore"] == nil)
    }

    @Test("TreedocsConfig defaults have expected values")
    func configDefaults() {
        let defaults = TreedocsConfig.defaults
        #expect(defaults.resolvedExclude.isEmpty)
        #expect(defaults.resolvedUseGitignore == true)
        #expect(defaults.resolvedMaxDescriptionLength == 120)
        #expect(defaults.resolvedIndentSize == 2)
        #expect(defaults.resolvedAlignColumns == false)
        #expect(defaults.resolvedCheckSeverity == .error)
        #expect(defaults.resolvedAutoInitEmpty == false)
        #expect(defaults.resolvedIcons == false)
    }

    @Test("TreedocsConfig merging nil returns self")
    func configMergingNil() {
        let config = TreedocsConfig(indentSize: 8)
        let merged = config.merging(nil)
        #expect(merged == config)
    }

    @Test("TreedocsConfig merging only overrides nil fields")
    func configMergingOverridesNilFields() {
        let base = TreedocsConfig(indentSize: 2, theme: "light")
        let other = TreedocsConfig(indentSize: 4, alignColumns: true)
        let merged = base.merging(other)
        #expect(merged.resolvedIndentSize == 4)
        #expect(merged.resolvedTheme == "light")
        #expect(merged.resolvedAlignColumns == true)
    }

    @Test("TreedocsConfig merging fully replaces unset fields")
    func configMergingAllFields() {
        let base = TreedocsConfig()
        let other = TreedocsConfig(
            exclude: ["tmp"],
            useGitignore: false,
            maxDescriptionLength: 200,
            indentSize: 4,
            alignColumns: true,
            checkSeverity: .warn,
            autoInitEmpty: true,
            theme: "dark",
            icons: true,
            aiProvider: "openai",
            aiModel: "gpt-4"
        )
        let merged = base.merging(other)
        #expect(merged.resolvedExclude == ["tmp"])
        #expect(merged.resolvedUseGitignore == false)
        #expect(merged.resolvedMaxDescriptionLength == 200)
        #expect(merged.resolvedIndentSize == 4)
        #expect(merged.resolvedAlignColumns == true)
        #expect(merged.resolvedCheckSeverity == .warn)
        #expect(merged.resolvedAutoInitEmpty == true)
        #expect(merged.resolvedTheme == "dark")
        #expect(merged.resolvedIcons == true)
        #expect(merged.aiProvider == "openai")
        #expect(merged.aiModel == "gpt-4")
    }

    @Test("parseString handles various input types")
    func parseStringVariants() {
        #expect(parseString("hello") == "hello")
        #expect(parseString(NSNumber(value: 42)) == "42")
        #expect(parseString(nil) == nil)
        #expect(parseString(123) == "123")
    }

    @Test("parseBool handles various input types")
    func parseBoolVariants() {
        #expect(parseBool(true) == true)
        #expect(parseBool(false) == false)
        #expect(parseBool(NSNumber(value: 1)) == true)
        #expect(parseBool(NSNumber(value: 0)) == false)
        #expect(parseBool("true") == true)
        #expect(parseBool("yes") == true)
        #expect(parseBool("1") == true)
        #expect(parseBool("false") == false)
        #expect(parseBool("no") == false)
        #expect(parseBool("0") == false)
        #expect(parseBool("invalid") == nil)
        #expect(parseBool(nil) == nil)
    }

    @Test("parseInt handles various input types")
    func parseIntVariants() {
        #expect(parseInt(42) == 42)
        #expect(parseInt(NSNumber(value: 99)) == 99)
        #expect(parseInt("123") == 123)
        #expect(parseInt("not-a-number") == nil)
        #expect(parseInt(nil) == nil)
    }

    @Test("parseStringArray handles nested types")
    func parseStringArrayVariants() {
        #expect(parseStringArray(["a", "b"]) == ["a", "b"])
        #expect(parseStringArray([1, 2]) == ["1", "2"])
        #expect(parseStringArray(nil) == nil)
        #expect(parseStringArray("not-array") == nil)
    }

    @Test("parseSeverity recognizes valid values")
    func parseSeverityVariants() {
        #expect(parseSeverity("error") == .error)
        #expect(parseSeverity("warn") == .warn)
        #expect(parseSeverity("ERROR") == .error)
        #expect(parseSeverity("Warn") == .warn)
        #expect(parseSeverity("invalid") == nil)
        #expect(parseSeverity(nil) == nil)
    }

    @Test("TreedocsConfig fromYAML parses all fields")
    func configFromYAMLAllFields() throws {
        let yaml = """
        exclude:
          - tmp
          - build
        use_gitignore: false
        max_description_length: 200
        indent_size: 4
        align_columns: true
        check_severity: warn
        auto_init_empty: true
        theme: dark
        icons: true
        ai_provider: openai
        ai_model: gpt-4
        """
        let parsed = try Yams.load(yaml: yaml)
        let config = try TreedocsConfig.fromYAML(parsed)
        #expect(config != nil)
        #expect(config?.resolvedExclude == ["tmp", "build"])
        #expect(config?.resolvedUseGitignore == false)
        #expect(config?.resolvedMaxDescriptionLength == 200)
        #expect(config?.resolvedIndentSize == 4)
        #expect(config?.resolvedAlignColumns == true)
        #expect(config?.resolvedCheckSeverity == .warn)
        #expect(config?.resolvedAutoInitEmpty == true)
        #expect(config?.resolvedTheme == "dark")
        #expect(config?.resolvedIcons == true)
        #expect(config?.aiProvider == "openai")
        #expect(config?.aiModel == "gpt-4")
    }

    @Test("TreedocsConfig fromYAML returns nil for nil input")
    func configFromYAMLNil() throws {
        let config = try TreedocsConfig.fromYAML(nil)
        #expect(config == nil)
    }

    @Test("TreedocsConfig fromYAML throws on non-mapping input")
    func configFromYAMLInvalid() throws {
        #expect(throws: TreeDocsError.self) {
            try TreedocsConfig.fromYAML("just a string")
        }
    }

    @Test("TreeEntry fromYAML throws on invalid input")
    func treeEntryFromYAMLInvalid() throws {
        #expect(throws: TreeDocsError.self) {
            try TreeEntry.fromYAML(123)
        }
    }

    @Test("EntryDocumentation fromYAML throws on invalid input")
    func entryDocumentationFromYAMLInvalid() throws {
        #expect(throws: TreeDocsError.self) {
            try EntryDocumentation.fromYAML(123)
        }
    }

    @Test("TreedocsFile.load throws on non-mapping root")
    func treedocsFileLoadInvalid() throws {
        #expect(throws: TreeDocsError.self) {
            try TreedocsFile.load(from: "just a string\n")
        }
    }

    @Test("ConfigLoader with non-existent global config path returns defaults")
    func configLoaderMissingGlobalConfig() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("README.md", contents: "test")
        let loader = ConfigLoader(globalConfigPath: workspace.root + Path("does-not-exist.yaml"))
        let loaded = try loader.load(root: workspace.root, stateOverrides: nil)
        #expect(loaded.config.resolvedIndentSize == 2)
        #expect(loaded.config.resolvedUseGitignore == true)
    }

    @Test("ConfigLoader merges empty project config with defaults")
    func configLoaderEmptyProjectConfig() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("README.md", contents: "test")
        try workspace.createDirectory(".treedocs")
        try workspace.writeFile(".treedocs/config.yaml", contents: "")
        let loader = ConfigLoader(globalConfigPath: nil)
        let loaded = try loader.load(root: workspace.root, stateOverrides: nil)
        #expect(loaded.config.resolvedIndentSize == 2)
    }
}
