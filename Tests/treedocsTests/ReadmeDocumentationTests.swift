import PathKit
import Testing
@testable import treedocs

@Suite("README Documentation")
struct ReadmeDocumentationTests {
    @Test
    func `README adapter maps supported fields and preserves unrelated content`() throws {
        let source = """
        ---
        title: Source guide
        description: Source code for the executable.
        references:
          - ../DOCS/Architecture.md
          - https://example.com/reference
        readme:
          description: Explains the source layout.
          references:
            - ../AGENTS.md
          audience: contributors
        custom: retained
        ---
        # Source guide
        Body text.
        """

        let candidate = try ReadmeDocumentationLoader().parse(source: source, relativePath: "Sources/README.md")
        let parsed = try #require(candidate)
        #expect(parsed.folderMetadata.description == "Source code for the executable.")
        #expect(parsed.folderMetadata.references == ["DOCS/Architecture.md", "https://example.com/reference"])
        #expect(parsed.readmeMetadata.description == "Explains the source layout.")
        #expect(parsed.readmeMetadata.references == ["AGENTS.md"])

        let rendered = try parsed.renderedSource()
        #expect(rendered.contains("title: Source guide"))
        #expect(rendered.contains("custom: retained"))
        #expect(rendered.contains("audience: contributors"))
        #expect(rendered.contains("# Source guide\nBody text."))
    }

    @Test
    func `README adapter ignores documents without supported metadata`() throws {
        let source = """
        ---
        title: Guide
        ---
        # Guide
        """

        #expect(try ReadmeDocumentationLoader().parse(source: source, relativePath: "README.md") == nil)
    }

    @Test
    func `README adapter rejects invalid supported field types`() {
        #expect(throws: TreeDocsError.self) {
            try ReadmeDocumentationLoader().parse(
                source: """
                ---
                description: [not, a, string]
                ---
                # Guide
                """,
                relativePath: "Guide/README.md"
            )
        }
    }

    @Test
    func `Reference normalization is repository safe and reversible`() throws {
        #expect(try ReadmeReferenceNormalizer.canonicalReference("../DOCS/Guide.md", folderPath: "Sources") == "DOCS/Guide.md")
        #expect(try ReadmeReferenceNormalizer.canonicalReference("[Guide](../DOCS/Guide.md)", folderPath: "Sources") == "[Guide](DOCS/Guide.md)")
        #expect(try ReadmeReferenceNormalizer.readmeReference("DOCS/Guide.md", folderPath: "Sources/Core") == "../../DOCS/Guide.md")
        #expect(throws: TreeDocsError.self) {
            try ReadmeReferenceNormalizer.canonicalReference("../../outside.md", folderPath: "Sources")
        }
    }

    @Test
    func `Reconciler imports nested metadata and defaults README descriptions`() throws {
        let candidate = try ReadmeDocumentationLoader().parse(
            source: """
            ---
            description: Core services.
            references: [../../DOCS/Architecture.md]
            ---
            # Core
            """,
            relativePath: "Sources/Core/README.md"
        )
        let source = try #require(candidate)
        let tree = [
            "Sources": TreeEntry(description: "", children: [
                "Core": TreeEntry(description: "", children: [
                    "README.md": TreeEntry(description: ""),
                ], isDirectory: true),
            ], isDirectory: true),
        ]

        let result = ReadmeReconciler().reconcile(sources: [source], tree: tree)
        #expect(TreeOperations.entry(at: "Sources/Core", in: result.tree)?.description == "Core services.")
        #expect(TreeOperations.entry(at: "Sources/Core", in: result.tree)?.references == ["DOCS/Architecture.md"])
        #expect(TreeOperations.entry(at: "Sources/Core/README.md", in: result.tree)?.description == "Overview and documentation for Sources/Core/.")
        #expect(result.conflicts.isEmpty)
    }

    @Test
    func `Root folder metadata is deferred while root README metadata imports`() throws {
        let candidate = try ReadmeDocumentationLoader().parse(
            source: """
            ---
            description: Deferred root folder description.
            readme:
              description: Project guide.
            ---
            # Project
            """,
            relativePath: "README.md"
        )
        let source = try #require(candidate)
        let result = ReadmeReconciler().reconcile(
            sources: [source],
            tree: ["README.md": TreeEntry(description: "")]
        )

        #expect(TreeOperations.entry(at: "README.md", in: result.tree)?.description == "Project guide.")
        #expect(result.warnings == ["README.md: root-folder README metadata is deferred; only readme.* metadata is used."])
        #expect(TreeOperations.entry(at: "_doc", in: result.tree) == nil)
    }

    @Test
    func `Root readme-only metadata opts in without a deferral warning`() throws {
        let candidate = try ReadmeDocumentationLoader().parse(
            source: """
            ---
            readme:
              references: []
            ---
            # Project
            """,
            relativePath: "README.md"
        )
        let source = try #require(candidate)
        let result = ReadmeReconciler().reconcile(
            sources: [source],
            tree: ["README.md": TreeEntry(description: "")]
        )

        #expect(TreeOperations.entry(at: "README.md", in: result.tree)?.description == "Project overview and documentation.")
        #expect(result.warnings.isEmpty)
    }

    @Test
    func `Reference equality ignores ordering`() throws {
        let candidate = try ReadmeDocumentationLoader().parse(
            source: """
            ---
            description: Sources.
            references: [../B.md, ../A.md]
            ---
            # Sources
            """,
            relativePath: "Sources/README.md"
        )
        let source = try #require(candidate)
        let tree = [
            "Sources": TreeEntry(description: "Sources.", references: ["A.md", "B.md"], children: [
                "README.md": TreeEntry(description: "Existing README description."),
            ], isDirectory: true),
        ]

        let result = ReadmeReconciler().reconcile(sources: [source], tree: tree)
        #expect(result.conflicts.isEmpty)
        #expect(result.pendingImports.isEmpty)
    }

    @Test
    func `Keeping treedocs updates only the conflicting README field`() throws {
        let candidate = try ReadmeDocumentationLoader().parse(
            source: """
            ---
            title: Preserved
            description: README value.
            ---
            # Sources
            Body.
            """,
            relativePath: "Sources/README.md"
        )
        let source = try #require(candidate)
        let tree = [
            "Sources": TreeEntry(description: "Treedocs value.", children: [
                "README.md": TreeEntry(description: "Existing README description."),
            ], isDirectory: true),
        ]
        var result = ReadmeReconciler().reconcile(sources: [source], tree: tree)
        let conflict = try #require(result.conflicts.first)

        try result.apply(resolutions: [conflict.id: .treedocs])
        let rendered = try #require(result.sources.first).renderedSource()
        #expect(rendered.contains("description: Treedocs value."))
        #expect(rendered.contains("title: Preserved"))
        #expect(rendered.contains("# Sources\nBody."))
    }

    @Test
    func `Transactional writer rolls back earlier replacements`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("one.md", contents: "one")
        try workspace.writeFile("two.md", contents: "two")
        let one = workspace.root + Path("one.md")
        let two = workspace.root + Path("two.md")
        var replacementCount = 0
        let writer = TransactionalFileWriter { source, path in
            replacementCount += 1
            if replacementCount == 2 {
                throw TreeDocsError.message("injected failure")
            }
            try source.write(to: path.url, atomically: true, encoding: .utf8)
        }

        #expect(throws: TreeDocsError.self) {
            try writer.write([
                PlannedTextFileWrite(path: one, expectedSource: "one", updatedSource: "ONE"),
                PlannedTextFileWrite(path: two, expectedSource: "two", updatedSource: "TWO"),
            ])
        }
        #expect(try String(contentsOf: one.url, encoding: .utf8) == "one")
        #expect(try String(contentsOf: two.url, encoding: .utf8) == "two")
    }

    @Test
    func `Transactional writer rejects a changed source before writing`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("README.md", contents: "changed")
        let path = workspace.root + Path("README.md")

        #expect(throws: TreeDocsError.self) {
            try TransactionalFileWriter().write([
                PlannedTextFileWrite(path: path, expectedSource: "original", updatedSource: "updated"),
            ])
        }
        #expect(try String(contentsOf: path.url, encoding: .utf8) == "changed")
    }
}
