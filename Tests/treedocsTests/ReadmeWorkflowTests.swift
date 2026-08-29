import PathKit
import Testing
@testable import treedocs

@Suite("README Workflow", .serialized)
struct ReadmeWorkflowTests {
    @Test
    func `Init imports nested folder and README metadata`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("Sources/README.md", contents: """
        ---
        description: Source files.
        references: [../DOCS/Architecture.md]
        readme:
          description: Source layout guide.
        ---
        # Sources
        """)
        try workspace.writeFile("DOCS/Architecture.md", contents: "# Architecture")

        let state = try workspace.service().initialize(at: workspace.root.string, force: false)
        #expect(TreeOperations.entry(at: "Sources", in: state.tree)?.description == "Source files.")
        #expect(TreeOperations.entry(at: "Sources", in: state.tree)?.references == ["DOCS/Architecture.md"])
        #expect(TreeOperations.entry(at: "Sources/README.md", in: state.tree)?.description == "Source layout guide.")
    }

    @Test
    func `Check reports pending README imports and sync imports them`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("Sources/README.md", contents: "# Sources")
        let service = try workspace.service()
        _ = try service.initialize(at: workspace.root.string, force: false)
        try workspace.writeFile("Sources/README.md", contents: """
        ---
        description: Source files.
        ---
        # Sources
        """)

        let report = try service.check(at: workspace.root.string)
        #expect(report.pendingReadmeImports.contains("Sources [description]"))
        #expect(report.hasIssues)

        let result = try service.syncResult(at: workspace.root.string, interactive: false)
        #expect(TreeOperations.entry(at: "Sources", in: result.file.tree)?.description == "Source files.")
        #expect(TreeOperations.entry(at: "Sources/README.md", in: result.file.tree)?.description == "Overview and documentation for Sources/.")
    }

    @Test
    func `Non-interactive conflicts leave README and treedocs unchanged`() throws {
        let workspace = try conflictingWorkspace()
        let service = try workspace.service()
        let statePath = workspace.root + Path("treedocs.yaml")
        let readmePath = workspace.root + Path("Sources/README.md")
        let stateBefore: String = try statePath.read()
        let readmeBefore: String = try readmePath.read()

        #expect(throws: TreeDocsError.self) {
            try service.syncResult(at: workspace.root.string, interactive: false)
        }
        #expect(try String(contentsOf: statePath.url, encoding: .utf8) == stateBefore)
        #expect(try String(contentsOf: readmePath.url, encoding: .utf8) == readmeBefore)
    }

    @Test
    func `Interactive keep treedocs writes README after all decisions`() throws {
        let workspace = try conflictingWorkspace()
        let service = try workspace.service()
        let check = try service.check(at: workspace.root.string)
        let conflict = try #require(check.readmeConflicts.first)
        let conflictCollector = StubReadmeConflictCollector(result: .resolve([conflict.id: .treedocs]))
        let missingCollector = StubMissingDescriptionCollector(result: .save([:]))

        let result = try service.syncResult(
            at: workspace.root.string,
            interactive: true,
            missingDescriptionCollector: missingCollector,
            readmeConflictCollector: conflictCollector
        )

        #expect(result.saved)
        #expect(conflictCollector.requestedConflicts == [conflict])
        #expect(TreeOperations.entry(at: "Sources", in: result.file.tree)?.description == "Treedocs source description.")
        let updatedReadme: String = try (workspace.root + Path("Sources/README.md")).read()
        #expect(updatedReadme.contains("description: Treedocs source description."))
        #expect(updatedReadme.contains("# Sources\nBody."))
    }

    @Test
    func `Interactive keep README updates treedocs without rewriting README`() throws {
        let workspace = try conflictingWorkspace()
        let service = try workspace.service()
        let readmePath = workspace.root + Path("Sources/README.md")
        let readmeBefore: String = try readmePath.read()
        let conflict = try #require(service.check(at: workspace.root.string).readmeConflicts.first)

        let result = try service.syncResult(
            at: workspace.root.string,
            interactive: true,
            missingDescriptionCollector: StubMissingDescriptionCollector(result: .save([:])),
            readmeConflictCollector: StubReadmeConflictCollector(result: .resolve([conflict.id: .readme]))
        )

        #expect(result.saved)
        #expect(TreeOperations.entry(at: "Sources", in: result.file.tree)?.description == "README source description.")
        #expect(try String(contentsOf: readmePath.url, encoding: .utf8) == readmeBefore)
    }

    @Test
    func `Cancelling README conflicts writes nothing`() throws {
        let workspace = try conflictingWorkspace()
        let service = try workspace.service()
        let statePath = workspace.root + Path("treedocs.yaml")
        let readmePath = workspace.root + Path("Sources/README.md")
        let stateBefore: String = try statePath.read()
        let readmeBefore: String = try readmePath.read()

        let result = try service.syncResult(
            at: workspace.root.string,
            interactive: true,
            missingDescriptionCollector: StubMissingDescriptionCollector(result: .save([:])),
            readmeConflictCollector: StubReadmeConflictCollector(result: .cancel)
        )

        #expect(!result.saved)
        #expect(try String(contentsOf: statePath.url, encoding: .utf8) == stateBefore)
        #expect(try String(contentsOf: readmePath.url, encoding: .utf8) == readmeBefore)
    }

    private func conflictingWorkspace() throws -> TestWorkspace {
        let workspace = try TestWorkspace()
        try workspace.writeFile("Sources/README.md", contents: """
        ---
        description: README source description.
        readme:
          description: Source guide.
        ---
        # Sources
        Body.
        """)
        let service = try workspace.service()
        _ = try service.initialize(at: workspace.root.string, force: false)
        var state = try workspace.loadState()
        TreeOperations.updateEntry(at: "Sources", in: &state.tree) { entry in
            entry.documentation = EntryDocumentation(description: "Treedocs source description.")
        }
        try workspace.saveState(state)
        return workspace
    }
}
