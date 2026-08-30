import PathKit
import Testing
@testable import treedocs

@Suite("README Workflow", .serialized)
struct ReadmeWorkflowTests {
    @Test
    func `Sync remains sparse unless README population is requested`() throws {
        let workspace = try populationWorkspace()
        let readmePath = workspace.root + Path("README.md")
        let before: String = try readmePath.read()

        _ = try workspace.service().syncResult(at: workspace.root.string, interactive: false)

        #expect(try String(contentsOf: readmePath.url, encoding: .utf8) == before)
        #expect(!before.contains("tree:"))
    }

    @Test
    func `README population supports children then recursive depths`() throws {
        let workspace = try populationWorkspace()
        let service = try workspace.service()
        let readmePath = workspace.root + Path("README.md")
        let plainReadmePath = workspace.root + Path("Plain/README.md")

        _ = try service.syncResult(
            at: workspace.root.string,
            interactive: false,
            populateReadmes: .children
        )
        let childrenSource: String = try readmePath.read()
        let children = try #require(try ReadmeDocumentationLoader().parse(source: childrenSource, relativePath: "README.md"))
        #expect(children.descendants.contains { $0.targetPath == "Root.txt" })
        #expect(children.descendants.contains { $0.targetPath == "Folder" })
        #expect(!children.descendants.contains { $0.targetPath == "Folder/Child.txt" })

        _ = try service.syncResult(
            at: workspace.root.string,
            interactive: false,
            populateReadmes: .recursive
        )
        let recursiveSource: String = try readmePath.read()
        let recursive = try #require(try ReadmeDocumentationLoader().parse(source: recursiveSource, relativePath: "README.md"))
        #expect(recursive.descendants.contains { $0.targetPath == "Folder/Child.txt" })
        #expect(recursive.descendants.contains { $0.targetPath == "Folder/Deep" })
        #expect(recursive.descendants.contains { $0.targetPath == "Folder/Deep/Grand.txt" })
        #expect(try String(contentsOf: plainReadmePath.url, encoding: .utf8) == "# Plain\n")
    }

    @Test
    func `Sync command parses README population depth and rejects invalid values`() throws {
        let children = try #require(try SyncCommand.parseAsRoot([
            "--populate-readmes", "children",
        ]) as? SyncCommand)
        let recursive = try #require(try SyncCommand.parseAsRoot([
            "--populate-readmes", "recursive",
        ]) as? SyncCommand)

        #expect(children.populateReadmes == .children)
        #expect(recursive.populateReadmes == .recursive)
        #expect(throws: (any Error).self) {
            try SyncCommand.parseAsRoot(["--populate-readmes", "descendants"])
        }
    }

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
    func `Init imports sparse descendants and ignores excluded or child-owned paths`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("README.md", contents: """
        ---
        readme:
          description: Project guide.
        tree:
          Visible.swift: Visible source.
          Ignored.swift: Ignored source.
          Nested:
            Hidden.swift: Child-owned source.
        ---
        # Project
        """)
        try workspace.writeFile("Visible.swift")
        try workspace.writeFile("Ignored.swift")
        try workspace.writeFile(".gitignore", contents: "Ignored.swift\n")
        try workspace.writeFile("Nested/Hidden.swift")
        try workspace.writeFile("Nested/treedocs.yaml")

        let state = try workspace.service().initialize(at: workspace.root.string, force: false)

        #expect(TreeOperations.entry(at: "Visible.swift", in: state.tree)?.description == "Visible source.")
        #expect(TreeOperations.entry(at: "Ignored.swift", in: state.tree) == nil)
        #expect(TreeOperations.entry(at: "Nested/Hidden.swift", in: state.tree) == nil)
    }

    @Test
    func `Check groups three source disagreement into one conflict`() throws {
        let workspace = try multiSourceConflictWorkspace()
        let report = try workspace.service().check(at: workspace.root.string)
        let conflict = try #require(report.readmeConflicts.first(where: { $0.targetPath == "Sources/File.swift" }))

        #expect(report.readmeConflicts.filter { $0.targetPath == "Sources/File.swift" }.count == 1)
        #expect(conflict.values.count == 3)
        #expect(conflict.readmeValues.map(\.readmePath) == ["README.md", "Sources/README.md"])
    }

    @Test
    func `Multi README reconciliation rolls back earlier replacements`() throws {
        let workspace = try multiSourceConflictWorkspace()
        var service = try workspace.service()
        let rootReadme = workspace.root + Path("README.md")
        let nestedReadme = workspace.root + Path("Sources/README.md")
        let statePath = workspace.root + Path("treedocs.yaml")
        let rootBefore: String = try rootReadme.read()
        let nestedBefore: String = try nestedReadme.read()
        let stateBefore: String = try statePath.read()
        let conflict = try #require(service.check(at: workspace.root.string).readmeConflicts.first)
        var replacements = 0
        service.transactionWriter = TransactionalFileWriter { source, path in
            replacements += 1
            if replacements == 2 {
                throw TreeDocsError.message("injected multi-source failure")
            }
            try source.write(to: path.url, atomically: true, encoding: .utf8)
        }

        #expect(throws: TreeDocsError.self) {
            try service.syncResult(
                at: workspace.root.string,
                interactive: true,
                missingDescriptionCollector: StubMissingDescriptionCollector(result: .save([:])),
                readmeConflictCollector: StubReadmeConflictCollector(
                    result: .resolve([conflict.id: .value(.description("Nested README value."))])
                )
            )
        }
        #expect(try String(contentsOf: rootReadme.url, encoding: .utf8) == rootBefore)
        #expect(try String(contentsOf: nestedReadme.url, encoding: .utf8) == nestedBefore)
        #expect(try String(contentsOf: statePath.url, encoding: .utf8) == stateBefore)
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
        let treedocsValue = try #require(conflict.treedocsValue)
        let conflictCollector = StubReadmeConflictCollector(result: .resolve([conflict.id: .value(treedocsValue)]))
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
            readmeConflictCollector: StubReadmeConflictCollector(
                result: .resolve([conflict.id: .value(try #require(conflict.readmeValues.first?.value))])
            )
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

    private func populationWorkspace() throws -> TestWorkspace {
        let workspace = try TestWorkspace()
        try workspace.writeFile("README.md", contents: """
        ---
        readme:
          description: Project guide.
        ---
        # Project
        """)
        try workspace.writeFile("Root.txt")
        try workspace.writeFile("Folder/Child.txt")
        try workspace.writeFile("Folder/Deep/Grand.txt")
        try workspace.writeFile("Plain/README.md", contents: "# Plain\n")
        _ = try workspace.service().initialize(at: workspace.root.string, force: false)

        var state = try workspace.loadState()
        let descriptions = [
            "Root.txt": "Root file.",
            "Folder": "Folder documentation.",
            "Folder/Child.txt": "Child file.",
            "Folder/Deep": "Deep folder.",
            "Folder/Deep/Grand.txt": "Grandchild file.",
            "Plain": "Plain folder.",
        ]
        TreeOperations.applyDescriptions(descriptions, to: &state.tree)
        try workspace.saveState(state)
        return workspace
    }

    private func multiSourceConflictWorkspace() throws -> TestWorkspace {
        let workspace = try TestWorkspace()
        try workspace.writeFile("README.md", contents: """
        ---
        readme:
          description: Project guide.
        ---
        # Project
        """)
        try workspace.writeFile("Sources/README.md", contents: """
        ---
        description: Sources.
        readme:
          description: Sources guide.
        ---
        # Sources
        """)
        try workspace.writeFile("Sources/File.swift")
        _ = try workspace.service().initialize(at: workspace.root.string, force: false)

        try workspace.writeFile("README.md", contents: """
        ---
        readme:
          description: Project guide.
        tree:
          Sources:
            File.swift: Root README value.
        ---
        # Project
        """)
        try workspace.writeFile("Sources/README.md", contents: """
        ---
        description: Sources.
        readme:
          description: Sources guide.
        tree:
          File.swift: Nested README value.
        ---
        # Sources
        """)
        var state = try workspace.loadState()
        TreeOperations.applyDescriptions(["Sources/File.swift": "Treedocs value."], to: &state.tree)
        try workspace.saveState(state)
        return workspace
    }
}
