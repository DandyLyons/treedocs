import ArgumentParser
import Foundation
import PathKit
import Testing
@testable import treedocs

@Suite("Documentation sources", .serialized)
struct DocumentationSourceTests {
    private func state(_ sources: [String: String]) -> TreedocsFile {
        TreedocsFile(
            schemaVersion: TreedocsSchemaMetadata.stagingVersion,
            project: ProjectMetadata(name: "Example", version: "1.0.0", lastUpdated: "2026-09-10"),
            overrides: TreedocsConfig(documentationSources: sources),
            signature: TreeSignature.make(from: []),
            tree: [:]
        )
    }

    @Test
    func exactSelectionFlowsThroughSyncCheckAndPopulation() throws {
        let workspace = try TestWorkspace()
        let ordinary = "---\ndescription: Wrong folder metadata\n---\n# Keep me\n"
        try workspace.writeFile(".github/README.md", contents: ordinary)
        try workspace.writeFile(".github/FOLDER.md", contents: """
        ---
        description: Automation
        file:
          description: Automation guide
          references: [../Guide.md]
        tree:
          workflow.yml: _
        ---
        # Body stays
        """)
        try workspace.writeFile(".github/workflow.yml")
        try workspace.writeFile(".github/workflows/README.md", contents: "---\ndescription: Workflows\n---\n")
        try workspace.writeFile("Guide.md")
        try workspace.saveState(state([".github/": "FOLDER.md"]))
        let service = try workspace.service()
        let result = try service.syncResult(at: workspace.root.string, interactive: false, populateReadmes: .recursive)
        #expect(TreeOperations.entry(at: ".github", in: result.file.tree)?.description == "Automation")
        #expect(TreeOperations.entry(at: ".github/workflows", in: result.file.tree)?.description == "Workflows")
        #expect(TreeOperations.entry(at: ".github/workflow.yml", in: result.file.tree)?.description == "_")
        #expect(TreeOperations.entry(at: ".github/FOLDER.md", in: result.file.tree)?.references == ["Guide.md"])
        #expect(TreeOperations.entry(at: ".github/README.md", in: result.file.tree) != nil)
        #expect(try String(contentsOf: (workspace.root + Path(".github/README.md")).url, encoding: .utf8) == ordinary)
        let source: String = try (workspace.root + Path(".github/FOLDER.md")).read()
        #expect(source.contains("# Body stays"))
        #expect(source.contains("workflows"))
        let report = try service.check(at: workspace.root.string)
        #expect(report.pendingReadmeImports.isEmpty)
        #expect(report.readmeConflicts.isEmpty)
    }

    @Test
    func missingAndExcludedExplicitSourcesNeverFallBack() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("Docs/README.md", contents: "---\ndescription: Fallback\n---\n")
        let sources = FolderDocumentationSourceSelection(overrides: ["Docs/": "FOLDER.md"])
        #expect(throws: (any Error).self) {
            try TreeScanner().scan(root: workspace.root, ignoreMatcher: IgnoreMatcher(patterns: []), sources: sources)
        }
        try workspace.writeFile("Docs/FOLDER.md")
        for pattern in ["Docs/FOLDER.md", "Docs/"] {
            #expect(throws: (any Error).self) {
                try TreeScanner().scan(root: workspace.root, ignoreMatcher: IgnoreMatcher(patterns: [pattern]), sources: sources)
            }
        }
    }

    @Test
    func defaultsAndNestedOwnership() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("README.md")
        try workspace.writeFile("Child/README.md")
        try workspace.writeFile("Nested/treedocs.yaml")
        try workspace.writeFile("Nested/README.md")
        let scan = try TreeScanner().scan(
            root: workspace.root,
            ignoreMatcher: IgnoreMatcher(patterns: []),
            sources: FolderDocumentationSourceSelection(overrides: ["Nested/": "MISSING.md", "Nested/Child/": "MISSING.md"])
        )
        #expect(scan.readmePaths == ["Child/README.md", "README.md"])
        #expect(scan.nestedBoundaries == ["Nested"])
    }

    @Test
    func creationUsesExactSourcesAndModernMetadata() throws {
        let workspace = try TestWorkspace()
        try workspace.createDirectory("Docs/Child/")
        try workspace.writeFile("Docs/README.md", contents: "# Existing\n")
        try workspace.saveState(state([".": "ROOT.md", "Docs/": "FOLDER.md"]))
        let before: String = try (workspace.root + Path("treedocs.yaml")).read()
        let service = try workspace.service()
        let created = try service.createReadmes(at: workspace.root.string, targetPath: ".", recursive: true)
        #expect(created.createdPaths == ["ROOT.md", "Docs/FOLDER.md", "Docs/Child/README.md"])
        let source: String = try (workspace.root + Path("Docs/FOLDER.md")).read()
        #expect(source.contains("file:"))
        #expect(!source.contains("readme:"))
        #expect(try String(contentsOf: (workspace.root + Path("treedocs.yaml")).url, encoding: .utf8) == before)
        #expect(try service.createReadmes(at: workspace.root.string, targetPath: "Docs/", recursive: false).skippedPaths == ["Docs/FOLDER.md"])
    }

    @Test
    func invalidConfigurationAndVersionGating() throws {
        for filename in ["", " ", ".", "..", "../DOC.md", "/DOC.md", "folder/DOC.md", "folder\\DOC.md"] {
            #expect(throws: (any Error).self) {
                try TreedocsConfig.fromYAML(["documentation_sources": ["Docs/": filename]])
            }
        }
        for folder in ["Docs", "/Docs/", "../Docs/", "Docs/../", "Docs//", "./Docs/"] {
            #expect(throws: (any Error).self) {
                try TreedocsConfig.fromYAML(["documentation_sources": [folder: "DOC.md"]])
            }
        }
        let staged = state([".": "ROOT.md", "Docs/": "DOC.md"])
        let yaml = try staged.toYAMLString()
        try TreedocsSchemaValidator().validate(yaml: yaml)
        #expect(try TreedocsFile.load(from: yaml).overrides?.documentationSources == staged.overrides?.documentationSources)
        #expect(throws: (any Error).self) {
            try TreedocsSchemaValidator().validate(yaml: yaml.replacingOccurrences(of: "0.3.0-WIP", with: "0.2.0"))
        }
    }

    @Test
    func legacyAndModernMetadataCannotSilentlyDisagree() throws {
        let loader = ReadmeDocumentationLoader()
        for key in ["file", "readme"] {
            let parsed = try loader.parse(source: "---\n\(key):\n  description: _\n---\nBody\n", relativePath: "DOC.md")
            #expect(parsed?.readmeMetadata.description == "_")
        }
        var same = try #require(try loader.parse(source: "---\nfile:\n  description: Same\nreadme:\n  description: Same\n---\nBody\n", relativePath: "DOC.md"))
        try same.set(.description("Resolved"), field: .description, target: .readme)
        let reparsed = try loader.parse(source: same.renderedSource(), relativePath: "DOC.md")
        #expect(reparsed?.readmeMetadata.description == "Resolved")
        for metadata in ["file: invalid", "file:\n  description: Different\nreadme:\n  description: Legacy", "file: {}\nreadme:\n  references: []"] {
            #expect(throws: (any Error).self) {
                try loader.parse(source: "---\n\(metadata)\n---\nBody\n", relativePath: "DOC.md")
            }
        }
    }

    @Test
    func commandAliases() throws {
        for name in ["createDoc", "createREADME"] {
            #expect(TreeDocsMain.rewrittenArguments(["treedocs", name, "Docs/"]) == [name, "Docs/"])
            #expect(try TreeDocs.parseAsRoot([name, "Docs/"]) is CreateReadmeCommand)
        }
        for name in ["--populate-docs", "--populate-readmes"] {
            let command = try #require(SyncCommand.parseAsRoot([name, "children"]) as? SyncCommand)
            #expect(command.populateReadmes == .children)
        }
    }

    @Test
    func creationRejectsExcludedSourcesAndTargetsBeneathNestedRoots() throws {
        let workspace = try TestWorkspace()
        try workspace.createDirectory("Nested/Child/")
        try workspace.createDirectory("Ignored/")
        try workspace.writeFile("Nested/treedocs.yaml")
        try workspace.writeFile(".gitignore", contents: "Ignored/\nFOLDER.md\n")
        try workspace.saveState(state([".": "FOLDER.md"]))
        let service = try workspace.service()
        for target in [".", "Ignored/", "Nested/Child/"] {
            #expect(throws: (any Error).self) {
                try service.createReadmes(at: workspace.root.string, targetPath: target, recursive: false)
            }
        }
        #expect(!(workspace.root + Path("FOLDER.md")).exists)
        #expect(!(workspace.root + Path("Nested/Child/README.md")).exists)
    }

    @Test
    func selectedSourceConflictsAreTransactionalAndResolvable() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("DOC.md", contents: "---\nfile:\n  description: Source\n---\nBody\n")
        var file = state([".": "DOC.md"])
        file.tree = ["DOC.md": TreeEntry(description: "Canonical")]
        try workspace.saveState(file)
        let before: String = try (workspace.root + Path("DOC.md")).read()
        let stateBefore: String = try (workspace.root + Path("treedocs.yaml")).read()
        let service = try workspace.service()
        #expect(throws: (any Error).self) {
            try service.syncResult(at: workspace.root.string, interactive: false)
        }
        #expect(try String(contentsOf: (workspace.root + Path("DOC.md")).url, encoding: .utf8) == before)
        #expect(try String(contentsOf: (workspace.root + Path("treedocs.yaml")).url, encoding: .utf8) == stateBefore)
        let scan = try TreeScanner().scan(root: workspace.root, ignoreMatcher: IgnoreMatcher(patterns: []), sources: FolderDocumentationSourceSelection(overrides: [".": "DOC.md"]))
        let sources = try ReadmeDocumentationLoader().load(root: workspace.root, readmePaths: scan.readmePaths)
        var reconciliation = ReadmeReconciler().reconcile(sources: sources, tree: file.tree)
        let conflict = try #require(reconciliation.conflicts.first)
        try reconciliation.apply(resolutions: [conflict.id: .value(.description("Canonical"))])
        let rendered = try #require(reconciliation.sources.first).renderedSource()
        #expect(rendered.contains("Canonical"))
        #expect(rendered.contains("Body"))
        #expect(rendered.contains("file:"))
    }
}
