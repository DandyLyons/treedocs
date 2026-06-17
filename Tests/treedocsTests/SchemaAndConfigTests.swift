import Foundation
import Testing
import PathKit
import Yams
@testable import treedocs

@Suite("Schema and Config")
struct SchemaAndConfigTests {
    @Test
    func `Canonical schema accepts InitialSpecs section 3_5 example`() throws {
        let yaml = """
        schema_version: "0.1.0"
        project:
          name: "ScraperBot"
          version: "2.1.0"
          last_updated: "2023-10-27"
        overrides:
          check_severity: "error"
          icons: true
        signature: "sha256:7a8b9c0d1e2f34567890abcdef1234567890abcdef1234567890abcdef123456"
        tree:
          src:
            _doc: "Main application source code"
            api:
              _doc: "REST endpoint definitions"
              auth.py: "Handles JWT validation and user sessions"
          Database:
            _doc:
              description: "Data persistence layer and migration scripts"
              references:
                - "DOCS/Database.md"
                - "DOCS/Schema.md"
                - "https://wiki.internal.com/db-standards"
          docs/architecture:
            _link: "src/api"
            _doc: "Alias to API folder for architectural reference"
          README.md: "Project entry point and installation guide"
        """

        try TreedocsSchemaValidator().validate(yaml: yaml)
    }

    @Test
    func `Validator rejects missing schema version before schema validation`() throws {
        let yaml = """
        project:
          name: Example
          version: "1.0.0"
          last_updated: "2026-06-13"
        signature: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        tree: {}
        """

        do {
            try TreedocsSchemaValidator().validate(yaml: yaml)
            Issue.record("Expected missing schema_version to fail")
        } catch {
            #expect(error.localizedDescription.contains("missing required root schema_version"))
        }
    }

    @Test
    func `Validator rejects unsupported future schema version before schema validation`() throws {
        let yaml = """
        schema_version: "99.0.0"
        project:
          name: Example
          version: "1.0.0"
          last_updated: "2026-06-13"
        signature: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        tree: {}
        """

        do {
            try TreedocsSchemaValidator().validate(yaml: yaml)
            Issue.record("Expected unsupported schema_version to fail")
        } catch {
            #expect(error.localizedDescription.contains("Unsupported treedocs.yaml schema_version \"99.0.0\""))
            #expect(error.localizedDescription.contains("This CLI supports: 0.1.0"))
        }
    }

    @Test
    func `Store rejects invalid schema fixture with field path`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("treedocs.yaml", contents: """
        schema_version: "0.1.0"
        project:
          name: Example
          version: "1.0.0"
          last_updated: "2026-06-13"
        signature: sha256:not-valid
        tree: {}
        """)

        do {
            _ = try workspace.loadState()
            Issue.record("Expected schema validation to reject invalid signature")
        } catch {
            #expect(error.localizedDescription.contains("#/signature"))
        }
    }

    @Test
    func `Generated treedocs file validates against canonical schema`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")

        _ = try service.initialize(at: workspace.root.string, force: false)

        try TreedocsSchemaValidator().validateFile(at: workspace.root + Path("treedocs.yaml"))
        try expectManagedSchemaMetadata(in: workspace)
    }

    @Test
    func `Sync and update rewrites include managed schema metadata`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")
        _ = try service.initialize(at: workspace.root.string, force: false)

        try workspace.writeFile("Sources/App.swift", contents: "print(\"hi\")")
        _ = try service.sync(at: workspace.root.string, interactive: false)
        try expectManagedSchemaMetadata(in: workspace)

        _ = try service.update(
            at: workspace.root.string,
            path: "README.md",
            description: "Project readme",
            addReferences: [],
            removeReferences: [],
            link: nil,
            clearLink: false
        )
        try expectManagedSchemaMetadata(in: workspace)
    }

    @Test
    func `Validator uses bundled schema instead of repository schema file`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")
        _ = try service.initialize(at: workspace.root.string, force: false)
        try workspace.writeFile("site/schemas/0.1.0/treedocs.schema.json", contents: "not json")

        try TreedocsSchemaValidator().validateFile(at: workspace.root + Path("treedocs.yaml"))
    }

    @Test
    func `Round-trip through store preserves valid tree structure`() throws {
        let workspace = try TestWorkspace()
        let file = TreedocsFile(
            project: ProjectMetadata(name: "Example", version: "1.0.0", lastUpdated: "2026-06-13"),
            signature: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tree: [
                "Sources": TreeEntry(description: "Source files", children: [
                    "main.swift": TreeEntry(description: "Entrypoint", references: ["DOCS/Main.md"]),
                    "Alias": TreeEntry(description: "Alias", link: "Sources/main.swift", isDirectory: true),
                ], isDirectory: true),
                "README.md": TreeEntry(description: "")
            ]
        )

        try workspace.saveState(file)
        var loaded = try workspace.loadState()
        loaded.tree["Package.swift"] = TreeEntry(description: "Manifest")
        try workspace.saveState(loaded)

        let roundTrip = try workspace.loadState()
        #expect(TreeOperations.entry(at: "Sources/main.swift", in: roundTrip.tree)?.references == ["DOCS/Main.md"])
        #expect(TreeOperations.entry(at: "Sources/Alias", in: roundTrip.tree)?.link == "Sources/main.swift")
        #expect(TreeOperations.entry(at: "README.md", in: roundTrip.tree)?.description == "")
        #expect(TreeOperations.entry(at: "Package.swift", in: roundTrip.tree)?.description == "Manifest")
    }

    @Test
    func `Store validates schema after saving`() throws {
        let workspace = try TestWorkspace()
        let file = TreedocsFile(
            project: ProjectMetadata(name: "Example", version: "1.0.0", lastUpdated: "2026-06-13"),
            signature: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tree: [
                "README.md": TreeEntry(description: "Project readme", references: ["http://example.com"])
            ]
        )

        do {
            try workspace.saveState(file)
            Issue.record("Expected save to reject schema-invalid references")
        } catch {
            #expect(error.localizedDescription.contains("#/tree/README.md/references/0"))
        }
    }

    @Test
    func `Store rewrites drop arbitrary YAML comments but keep managed schema header and structured notes`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("treedocs.yaml", contents: """
        # Root-level comment that should not survive serialization.
        schema_version: "0.1.0"
        project:
          name: Example
          version: "1.0.0"
          last_updated: "2026-06-13"
        signature: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        tree:
          README.md:
            # Inline note that belongs in references instead.
            description: Project readme
            references:
              - DOCS/README.md
        """)

        var loaded = try workspace.loadState()
        loaded.tree["Package.swift"] = TreeEntry(description: "Package manifest")
        try workspace.saveState(loaded)

        let rewritten = try String(contentsOf: (workspace.root + Path("treedocs.yaml")).url, encoding: .utf8)
        let roundTrip = try workspace.loadState()
        #expect(!rewritten.contains("Root-level comment"))
        #expect(!rewritten.contains("Inline note"))
        try expectManagedSchemaMetadata(in: workspace)
        #expect(TreeOperations.entry(at: "README.md", in: roundTrip.tree)?.references == ["DOCS/README.md"])
        #expect(TreeOperations.entry(at: "Package.swift", in: roundTrip.tree)?.description == "Package manifest")
    }

    @Test
    func `YAML schema round-trips strings, objects, nested folders, links, and references`() throws {
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

    @Test
    func `Config precedence applies defaults, global config, project config, and state overrides`() throws {
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

    @Test
    func `Empty YAML produces a default TreedocsFile`() throws {
        let file = try TreedocsFile.load(from: "")
        #expect(file.project.isEmpty)
        #expect(file.overrides == nil)
        #expect(file.signature == nil)
        #expect(file.tree.isEmpty)
    }

    @Test
    func `YAML with only project section parses correctly`() throws {
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

    @Test
    func `YAML with only signature parses correctly`() throws {
        let yaml = "signature: sha256:abc123\n"
        let file = try TreedocsFile.load(from: yaml)
        #expect(file.signature == "sha256:abc123")
        #expect(file.tree.isEmpty)
    }

    @Test
    func `TreedocsFile default initializer produces empty state`() {
        let file = TreedocsFile()
        #expect(file.project.isEmpty)
        #expect(file.overrides == nil)
        #expect(file.signature == nil)
        #expect(file.tree.isEmpty)
    }

    @Test
    func `EntryDocumentation round-trips as simple string`() {
        let doc = EntryDocumentation(description: "Hello world")
        #expect(doc.toYAMLValue() as? String == "Hello world")
        #expect(!doc.isEmpty)
    }

    @Test
    func `EntryDocumentation round-trips as mapping with references`() {
        let doc = EntryDocumentation(description: "Hello", references: ["ref1", "ref2"])
        let value = doc.toYAMLValue() as? [String: Any]
        #expect(value != nil)
        #expect(value?["description"] as? String == "Hello")
        #expect(value?["references"] as? [String] == ["ref1", "ref2"])
    }

    @Test
    func `EntryDocumentation with only references round-trips`() {
        let doc = EntryDocumentation(references: ["ref1"])
        let value = doc.toYAMLValue() as? [String: Any]
        #expect(value?["description"] == nil)
        #expect(value?["references"] as? [String] == ["ref1"])
    }

    @Test
    func `EntryDocumentation isEmpty for nil description and no references`() {
        let doc = EntryDocumentation()
        #expect(doc.isEmpty)

        let docWithDescription = EntryDocumentation(description: "text")
        #expect(!docWithDescription.isEmpty)

        let docWithRefs = EntryDocumentation(references: ["r"])
        #expect(!docWithRefs.isEmpty)
    }

    @Test
    func `EntryDocumentation fromYAML parses string`() throws {
        let doc = try EntryDocumentation.fromYAML("Some description")
        #expect(doc?.description == "Some description")
        #expect(doc?.references.isEmpty == true)
    }

    @Test
    func `EntryDocumentation fromYAML parses mapping`() throws {
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

    @Test
    func `EntryDocumentation fromYAML returns nil for nil input`() throws {
        let doc = try EntryDocumentation.fromYAML(nil)
        #expect(doc == nil)
    }

    @Test
    func `TreeEntry as simple string leaf`() throws {
        let entry = try TreeEntry.fromYAML("Simple description")
        #expect(entry.description == "Simple description")
        #expect(!entry.isDirectory)
        #expect(entry.children.isEmpty)
    }

    @Test
    func `TreeEntry as mapping with description`() throws {
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

    @Test
    func `TreeEntry as directory with children`() throws {
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

    @Test
    func `TreeEntry toYAMLValue for leaf with description`() {
        let entry = TreeEntry(description: "Leaf file")
        let value = entry.toYAMLValue()
        #expect(value as? String == "Leaf file")
    }

    @Test
    func `TreeEntry toYAMLValue for leaf with link`() {
        let entry = TreeEntry(description: "Leaf", link: "target")
        let value = entry.toYAMLValue() as? [String: Any]
        #expect(value?["description"] as? String == "Leaf")
        #expect(value?["_link"] as? String == "target")
    }

    @Test
    func `TreeEntry toYAMLValue for directory`() {
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

    @Test
    func `TreedocsConfig toYAMLValue omits nil fields`() {
        let config = TreedocsConfig(indentSize: 4, theme: "dark")
        let value = config.toYAMLValue()
        #expect(value["indent_size"] as? Int == 4)
        #expect(value["theme"] as? String == "dark")
        #expect(value["exclude"] == nil)
        #expect(value["use_gitignore"] == nil)
    }

    @Test
    func `TreedocsConfig defaults have expected values`() {
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

    @Test
    func `TreedocsConfig merging nil returns self`() {
        let config = TreedocsConfig(indentSize: 8)
        let merged = config.merging(nil)
        #expect(merged == config)
    }

    @Test
    func `TreedocsConfig merging only overrides nil fields`() {
        let base = TreedocsConfig(indentSize: 2, theme: "light")
        let other = TreedocsConfig(indentSize: 4, alignColumns: true)
        let merged = base.merging(other)
        #expect(merged.resolvedIndentSize == 4)
        #expect(merged.resolvedTheme == "light")
        #expect(merged.resolvedAlignColumns == true)
    }

    @Test
    func `TreedocsConfig merging fully replaces unset fields`() {
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

    @Test
    func `parseString handles various input types`() {
        #expect(parseString("hello") == "hello")
        #expect(parseString(NSNumber(value: 42)) == "42")
        #expect(parseString(nil) == nil)
        #expect(parseString(123) == "123")
    }

    @Test
    func `parseBool handles various input types`() {
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

    @Test
    func `parseInt handles various input types`() {
        #expect(parseInt(42) == 42)
        #expect(parseInt(NSNumber(value: 99)) == 99)
        #expect(parseInt("123") == 123)
        #expect(parseInt("not-a-number") == nil)
        #expect(parseInt(nil) == nil)
    }

    @Test
    func `parseStringArray handles nested types`() {
        #expect(parseStringArray(["a", "b"]) == ["a", "b"])
        #expect(parseStringArray([1, 2]) == ["1", "2"])
        #expect(parseStringArray(nil) == nil)
        #expect(parseStringArray("not-array") == nil)
    }

    @Test
    func `parseSeverity recognizes valid values`() {
        #expect(parseSeverity("error") == .error)
        #expect(parseSeverity("warn") == .warn)
        #expect(parseSeverity("ERROR") == .error)
        #expect(parseSeverity("Warn") == .warn)
        #expect(parseSeverity("invalid") == nil)
        #expect(parseSeverity(nil) == nil)
    }

    @Test
    func `TreedocsConfig fromYAML parses all fields`() throws {
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

    @Test
    func `TreedocsConfig fromYAML returns nil for nil input`() throws {
        let config = try TreedocsConfig.fromYAML(nil)
        #expect(config == nil)
    }

    @Test
    func `TreedocsConfig fromYAML throws on non-mapping input`() throws {
        #expect(throws: TreeDocsError.self) {
            try TreedocsConfig.fromYAML("just a string")
        }
    }

    @Test
    func `TreeEntry fromYAML throws on invalid input`() throws {
        #expect(throws: TreeDocsError.self) {
            try TreeEntry.fromYAML(123)
        }
    }

    @Test
    func `EntryDocumentation fromYAML throws on invalid input`() throws {
        #expect(throws: TreeDocsError.self) {
            try EntryDocumentation.fromYAML(123)
        }
    }

    @Test
    func `TreedocsFile.load throws on non-mapping root`() throws {
        #expect(throws: TreeDocsError.self) {
            try TreedocsFile.load(from: "just a string\n")
        }
    }

    @Test
    func `ConfigLoader with non-existent global config path returns defaults`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("README.md", contents: "test")
        let loader = ConfigLoader(globalConfigPath: workspace.root + Path("does-not-exist.yaml"))
        let loaded = try loader.load(root: workspace.root, stateOverrides: nil)
        #expect(loaded.config.resolvedIndentSize == 2)
        #expect(loaded.config.resolvedUseGitignore == true)
    }

    @Test
    func `ConfigLoader merges empty project config with defaults`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("README.md", contents: "test")
        try workspace.createDirectory(".treedocs")
        try workspace.writeFile(".treedocs/config.yaml", contents: "")
        let loader = ConfigLoader(globalConfigPath: nil)
        let loaded = try loader.load(root: workspace.root, stateOverrides: nil)
        #expect(loaded.config.resolvedIndentSize == 2)
    }
}

private func expectManagedSchemaMetadata(in workspace: TestWorkspace) throws {
    let yaml = try String(contentsOf: (workspace.root + Path("treedocs.yaml")).url, encoding: .utf8)
    let file = try TreedocsFile.load(from: yaml)
    let expectedHeader = TreedocsSchemaMetadata.languageServerHeader(for: file.schemaVersion)

    #expect(file.schemaVersion == TreedocsSchemaMetadata.currentVersion)
    #expect(yaml.hasPrefix("\(expectedHeader)\n"))
    #expect(yaml.contains("schema_version:"))
    #expect(expectedHeader.contains("/schemas/\(file.schemaVersion)/"))
}
