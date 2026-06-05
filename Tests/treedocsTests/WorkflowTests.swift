import Testing
@testable import treedocs

@Suite("Workflow")
struct WorkflowTests {
    @Test
    func `Init creates treedocs.yaml and sync preserves existing descriptions while adding and removing paths`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")
        try workspace.createDirectory("Sources")
        try workspace.writeFile("Sources/App.swift", contents: "print(\"hi\")")

        _ = try service.initialize(at: workspace.root.string, force: false)
        var state = try workspace.loadState()
        #expect(TreeOperations.entry(at: "README.md", in: state.tree) != nil)
        #expect(state.project.name == workspace.root.lastComponent)
        #expect(state.project.version == "0.0.0")
        #expect(state.project.lastUpdated?.count == 10)
        #expect(TreeOperations.entry(at: "README.md", in: state.tree)?.description == "")
        #expect(TreeOperations.entry(at: "Sources", in: state.tree)?.description == "")

        state.tree = TreeOperations.mergePreservingMetadata(
            scanned: state.tree,
            existing: ["README.md": TreeEntry(description: "Project readme")]
        )
        try workspace.saveState(state)

        try workspace.writeFile("Sources/New.swift", contents: "print(\"new\")")
        try workspace.remove("Sources/App.swift")

        let synced = try service.sync(at: workspace.root.string, interactive: false)
        #expect(TreeOperations.entry(at: "README.md", in: synced.tree)?.description == "Project readme")
        #expect(TreeOperations.entry(at: "Sources/New.swift", in: synced.tree)?.description == "")
        #expect(TreeOperations.entry(at: "Sources/App.swift", in: synced.tree) == nil)
    }

    @Test
    func `Check reports clean and stale trees with severity-aware failure behavior`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")

        _ = try service.initialize(at: workspace.root.string, force: false)
        _ = try service.update(
            at: workspace.root.string,
            path: "README.md",
            description: "Project readme",
            addReferences: [],
            removeReferences: [],
            link: nil,
            clearLink: false
        )

        var cleanReport = try service.check(at: workspace.root.string)
        #expect(!cleanReport.hasIssues)
        #expect(!cleanReport.shouldFail)

        try workspace.writeFile("New.swift", contents: "print(\"new\")")
        let staleReport = try service.check(at: workspace.root.string)
        #expect(staleReport.hasSignatureDrift)
        #expect(staleReport.shouldFail)

        var state = try workspace.loadState()
        state.overrides = TreedocsConfig(checkSeverity: .warn)
        try workspace.saveState(state)

        cleanReport = try service.check(at: workspace.root.string)
        #expect(cleanReport.hasIssues)
        #expect(!cleanReport.shouldFail)
    }

    @Test
    func `Inspect resolves direct links, chained links, and cycle errors`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("README.md", contents: "demo")
        try workspace.saveState(
            TreedocsFile(
                signature: "sha256:test",
                tree: [
                    "src": TreeEntry(description: "Source", children: [
                        "api": TreeEntry(description: "API", isDirectory: true),
                    ], isDirectory: true),
                    "docs": TreeEntry(children: [
                        "architecture": TreeEntry(description: "Architecture alias", link: "src/api", isDirectory: true),
                    ], isDirectory: true),
                    "alias": TreeEntry(link: "docs/architecture", isDirectory: true),
                    "cycle-a": TreeEntry(link: "cycle-b"),
                    "cycle-b": TreeEntry(link: "cycle-a"),
                ]
            )
        )

        let service = try workspace.service()
        let direct = try service.inspect(at: workspace.root.string, path: "docs/architecture", recursive: false)
        #expect(direct.linkResolution == .resolved(path: "src/api", chain: ["docs/architecture", "src/api"], entry: TreeEntry(description: "API", isDirectory: true)))

        let chained = try service.inspect(at: workspace.root.string, path: "alias", recursive: false)
        if case let .resolved(path, chain, _) = chained.linkResolution {
            #expect(path == "src/api")
            #expect(chain == ["alias", "docs/architecture", "src/api"])
        } else {
            Issue.record("Expected chained link resolution")
        }

        let cycle = try service.inspect(at: workspace.root.string, path: "cycle-a", recursive: false)
        if case let .cycle(chain) = cycle.linkResolution {
            #expect(chain == ["cycle-a", "cycle-b", "cycle-a"])
        } else {
            Issue.record("Expected a cycle result")
        }
    }

    @Test
    func `Update mutates descriptions and references and refreshes the signature`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")

        let initial = try service.initialize(at: workspace.root.string, force: false)
        let initialSignature = initial.signature
        try workspace.writeFile("Sources.swift", contents: "print(\"new\")")

        let updated = try service.update(
            at: workspace.root.string,
            path: "README.md",
            description: "Project readme",
            addReferences: ["DOCS/README.md", "https://example.com"],
            removeReferences: ["https://example.com"],
            link: nil,
            clearLink: false
        )

        #expect(updated.signature != initialSignature)
        #expect(TreeOperations.entry(at: "README.md", in: updated.tree)?.description == "Project readme")
        #expect(TreeOperations.entry(at: "README.md", in: updated.tree)?.references == ["DOCS/README.md"])
    }

    @Test
    func `ls renders refs and links and path returns a raw matching path`() throws {
        let workspace = try TestWorkspace()
        try workspace.saveState(
            TreedocsFile(
                overrides: TreedocsConfig(maxDescriptionLength: 18, indentSize: 4),
                signature: "sha256:test",
                tree: [
                    "src": TreeEntry(description: "Source", children: [
                        "api": TreeEntry(description: "REST endpoint definitions", references: ["DOCS/API.md"], isDirectory: true),
                    ], isDirectory: true),
                    "docs": TreeEntry(children: [
                        "architecture": TreeEntry(description: "Architecture", link: "src/api", isDirectory: true),
                    ], isDirectory: true),
                ]
            )
        )

        let service = try workspace.service()
        let rendered = try service.renderTree(at: workspace.root.string, subtreePath: nil)
        #expect(rendered.contains("    api/ [ref]"))
        #expect(rendered.contains("architecture/ [link->src/api]"))
        #expect(rendered.contains("REST endpoint d..."))

        let path = try service.findPath(at: workspace.root.string, query: "endpoint")
        #expect(path == "src/api")
        let missing = try service.findPath(at: workspace.root.string, query: "missing")
        #expect(missing == nil)
    }

    @Test
    func `Show warns on validation issues and renders requested subtree`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("Sources/App.swift", contents: "print(\"hi\")")
        _ = try service.initialize(at: workspace.root.string, force: false)

        try workspace.writeFile("Sources/New.swift", contents: "print(\"new\")")

        let checkedOutput = try service.show(at: workspace.root.string, path: "Sources", checkFirst: true)
        #expect(checkedOutput.contains("Warning: treedocs discrepancies found"))
        #expect(checkedOutput.contains("App.swift"))

        let uncheckedOutput = try service.show(at: workspace.root.string, path: "Sources", checkFirst: false)
        #expect(!uncheckedOutput.contains("Warning: treedocs discrepancies found"))
        #expect(uncheckedOutput.contains("App.swift"))
    }

    @Test
    func `Config file discovery and fill prompt support command scaffolding`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")
        _ = try service.initialize(at: workspace.root.string, force: false)
        try workspace.writeFile(".treedocs/config.yaml", contents: "check_severity: warn")
        try workspace.writeFile(".treedocs/.treedocs_ignore", contents: "Generated")
        try workspace.writeFile("Vendor/Plugin/treedocs.yaml", contents: "project:\n  name: plugin\ntree: {}")

        let files = try service.configFiles(at: workspace.root.string, under: ".")
        #expect(files == [
            ".treedocs/.treedocs_ignore",
            ".treedocs/config.yaml",
            "Vendor/Plugin/treedocs.yaml",
            "treedocs.yaml",
        ])

        let prompt = try service.fillPrompt(at: workspace.root.string)
        #expect(prompt.contains("Fill missing descriptions"))
        #expect(prompt.contains("DOCS/treedocs.schema.json"))
    }
}
