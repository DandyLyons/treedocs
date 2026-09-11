import ArgumentParser
import Foundation
import PathKit
import Testing
@testable import treedocs

@Suite("Create README", .serialized)
struct CreateReadmeTests {
    @Test
    func `Nested README copies folder metadata and renders relative references`() throws {
        let workspace = try TestWorkspace()
        try workspace.createDirectory("Sources/Core")
        try workspace.saveState(createReadmeState(
            projectName: "Example",
            tree: [
                "Sources": TreeEntry(description: "Sources.", children: [
                    "Core": TreeEntry(
                        description: " Core scanning and reconciliation logic. ",
                        references: [
                            "DOCS/architecture.md",
                            "DOCS/architecture.md",
                            "[Guide](DOCS/guide.md)",
                            "https://example.com/reference",
                        ],
                        children: [:],
                        isDirectory: true
                    ),
                ], isDirectory: true),
            ]
        ))
        let stateBefore = try (workspace.root + Path("treedocs.yaml")).read()

        let result = try workspace.service().createReadmes(
            at: workspace.root.string,
            targetPath: "Sources/Core",
            recursive: false
        )

        #expect(result == CreateReadmeResult(createdPaths: ["Sources/Core/README.md"], skippedPaths: []))
        let source: String = try (workspace.root + Path("Sources/Core/README.md")).read()
        #expect(source.hasSuffix("\n"))
        #expect(source.contains("# Core\n"))
        let candidate = try ReadmeDocumentationLoader().parse(
            source: source,
            relativePath: "Sources/Core/README.md"
        )
        let parsed = try #require(candidate)
        #expect(parsed.folderMetadata.description == "Core scanning and reconciliation logic.")
        #expect(parsed.folderMetadata.references == [
            "DOCS/architecture.md",
            "[Guide](DOCS/guide.md)",
            "https://example.com/reference",
        ])
        #expect(parsed.readmeMetadata.description == "Overview and documentation for Sources/Core/.")
        #expect(try (workspace.root + Path("treedocs.yaml")).read() == stateBefore)
    }

    @Test
    func `Root README uses project heading and omits root folder metadata`() throws {
        let workspace = try TestWorkspace()
        try workspace.saveState(createReadmeState(
            projectName: "Example Project",
            tree: ["Child": TreeEntry(description: "Not root metadata.", children: [:], isDirectory: true)]
        ))

        let result = try workspace.service().createReadmes(
            at: workspace.root.string,
            targetPath: ".",
            recursive: false
        )

        #expect(result.createdPaths == ["README.md"])
        let source: String = try (workspace.root + Path("README.md")).read()
        let candidate = try ReadmeDocumentationLoader().parse(source: source, relativePath: "README.md")
        let parsed = try #require(candidate)
        #expect(parsed.folderMetadata.isEmpty)
        #expect(parsed.readmeMetadata.description == "Project overview and documentation.")
        #expect(source.contains("# Example Project\n"))
    }

    @Test
    func `Nested README is created when treedocs has no folder metadata`() throws {
        let workspace = try TestWorkspace()
        try workspace.createDirectory("Undocumented")
        try workspace.saveState(createReadmeState(tree: [:]))

        let result = try workspace.service().createReadmes(
            at: workspace.root.string,
            targetPath: "Undocumented",
            recursive: false
        )

        #expect(result.createdPaths == ["Undocumented/README.md"])
        let source: String = try (workspace.root + Path("Undocumented/README.md")).read()
        let candidate = try ReadmeDocumentationLoader().parse(
            source: source,
            relativePath: "Undocumented/README.md"
        )
        let parsed = try #require(candidate)
        #expect(parsed.folderMetadata.isEmpty)
        #expect(parsed.readmeMetadata.description == "Overview and documentation for Undocumented/.")
        #expect(source.contains("# Undocumented\n"))
    }

    @Test
    func `Recursive creation respects ignores boundaries symlinks and existing exact READMEs`() throws {
        let workspace = try TestWorkspace()
        let external = try TestWorkspace()
        try workspace.createDirectory("Docs/.build/Generated")
        try workspace.createDirectory("Docs/Boundary/Owned")
        try workspace.createDirectory("Docs/Existing")
        try workspace.createDirectory("Docs/Ignored")
        try workspace.createDirectory("Docs/Visible")
        try workspace.writeFile("Docs/Boundary/treedocs.yaml", contents: "schema_version: 0.2.0\ntree: {}\n")
        try workspace.writeFile("Docs/Existing/README.md", contents: "KEEP EXACTLY")
        try workspace.writeFile(".gitignore", contents: "Docs/Ignored/\n")
        try external.createDirectory("Outside")
        try FileManager.default.createSymbolicLink(
            atPath: (workspace.root + Path("Docs/ExternalLink")).string,
            withDestinationPath: (external.root + Path("Outside")).string
        )
        try workspace.saveState(createReadmeState(projectName: "Example", tree: [:]))

        let result = try workspace.service().createReadmes(
            at: workspace.root.string,
            targetPath: "Docs",
            recursive: true
        )

        #expect(result.createdPaths == [
            "Docs/README.md",
            "Docs/Boundary/README.md",
            "Docs/Visible/README.md",
        ])
        #expect(result.skippedPaths == ["Docs/Existing/README.md"])
        #expect(try (workspace.root + Path("Docs/Existing/README.md")).read() == "KEEP EXACTLY")
        #expect(!(workspace.root + Path("Docs/Boundary/Owned/README.md")).exists)
        #expect(!(workspace.root + Path("Docs/Ignored/README.md")).exists)
        #expect(!(workspace.root + Path("Docs/.build/README.md")).exists)
        #expect(!(external.root + Path("Outside/README.md")).exists)
        #expect(CreateReadmeCommand.summaryLines(for: result) == [
            "Created documentation files:",
            "- Docs/README.md",
            "- Docs/Boundary/README.md",
            "- Docs/Visible/README.md",
            "Skipped existing documentation files:",
            "- Docs/Existing/README.md",
            "Created 3, skipped 1.",
            "Next step: run `treedocs sync`.",
        ])
    }

    @Test
    func `Differently cased readme is never treated as an existing exact README`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("Docs/readme.md", contents: "preserve lowercase")
        try workspace.saveState(createReadmeState(tree: [:]))
        let exactNameAliasesLowercase = (workspace.root + Path("Docs/README.md")).exists

        if exactNameAliasesLowercase {
            #expect(throws: TreeDocsError.self) {
                try workspace.service().createReadmes(
                    at: workspace.root.string,
                    targetPath: "Docs",
                    recursive: false
                )
            }
        } else {
            let result = try workspace.service().createReadmes(
                at: workspace.root.string,
                targetPath: "Docs",
                recursive: false
            )
            #expect(result.createdPaths == ["Docs/README.md"])
            #expect(result.skippedPaths.isEmpty)
        }
        #expect(try (workspace.root + Path("Docs/readme.md")).read() == "preserve lowercase")
    }

    @Test
    func `All existing READMEs succeed with a no files created summary`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("Docs/README.md", contents: "existing")
        try workspace.saveState(createReadmeState(tree: [:]))

        let result = try workspace.service().createReadmes(
            at: workspace.root.string,
            targetPath: "Docs",
            recursive: false
        )

        #expect(result == CreateReadmeResult(createdPaths: [], skippedPaths: ["Docs/README.md"]))
        #expect(CreateReadmeCommand.summaryLines(for: result) == [
            "No files created.",
            "Skipped existing documentation files:",
            "- Docs/README.md",
            "Created 0, skipped 1.",
        ])
    }

    @Test
    func `Invalid and escaping targets fail before creating files`() throws {
        let workspace = try TestWorkspace()
        let external = try TestWorkspace()
        try workspace.writeFile("NotADirectory.txt", contents: "file")
        try FileManager.default.createSymbolicLink(
            atPath: (workspace.root + Path("OutsideLink")).string,
            withDestinationPath: external.root.string
        )
        try workspace.saveState(createReadmeState(tree: [:]))
        let service = try workspace.service()

        #expect(throws: TreeDocsError.self) {
            try service.createReadmes(at: workspace.root.string, targetPath: "Missing", recursive: true)
        }
        #expect(throws: TreeDocsError.self) {
            try service.createReadmes(at: workspace.root.string, targetPath: "NotADirectory.txt", recursive: true)
        }
        #expect(throws: TreeDocsError.self) {
            try service.createReadmes(at: workspace.root.string, targetPath: "treedocs.yaml", recursive: true)
        }
        #expect(throws: TreeDocsError.self) {
            try service.createReadmes(at: workspace.root.string, targetPath: external.root.string, recursive: true)
        }
        #expect(throws: TreeDocsError.self) {
            try service.createReadmes(at: workspace.root.string, targetPath: "OutsideLink", recursive: true)
        }
        #expect(!(workspace.root + Path("README.md")).exists)
        #expect(!(external.root + Path("README.md")).exists)
    }

    @Test
    func `Write failure rolls back files created earlier in the invocation`() throws {
        let workspace = try TestWorkspace()
        try workspace.createDirectory("Docs/Alpha")
        try workspace.createDirectory("Docs/Beta")
        try workspace.writeFile("Docs/Existing/README.md", contents: "preserve")
        try workspace.saveState(createReadmeState(tree: [:]))

        var writeCount = 0
        var service = try workspace.service()
        service.readmeStubWriter = TransactionalReadmeStubWriter { source, path in
            writeCount += 1
            if writeCount == 3 {
                throw TreeDocsError.message("injected failure")
            }
            try Data(source.utf8).write(to: path.url, options: .withoutOverwriting)
        }

        #expect(throws: TreeDocsError.self) {
            try service.createReadmes(at: workspace.root.string, targetPath: "Docs", recursive: true)
        }
        #expect(!(workspace.root + Path("Docs/README.md")).exists)
        #expect(!(workspace.root + Path("Docs/Alpha/README.md")).exists)
        #expect(!(workspace.root + Path("Docs/Beta/README.md")).exists)
        #expect(try (workspace.root + Path("Docs/Existing/README.md")).read() == "preserve")
    }

    @Test
    func `Writer rejects a destination that appears before writing`() throws {
        let workspace = try TestWorkspace()
        try workspace.createDirectory("Docs")
        try workspace.writeFile("Docs/README.md", contents: "appeared")
        let other = workspace.root + Path("Other.md")

        #expect(throws: TreeDocsError.self) {
            try TransactionalReadmeStubWriter().write([
                PlannedReadmeStubCreation(
                    path: workspace.root + Path("Docs/README.md"),
                    relativePath: "Docs/README.md",
                    source: "replacement"
                ),
                PlannedReadmeStubCreation(path: other, relativePath: "Other.md", source: "other"),
            ])
        }
        #expect(try (workspace.root + Path("Docs/README.md")).read() == "appeared")
        #expect(!other.exists)
    }

    @Test
    func `Command preserves its exact name and recursive short flag`() throws {
        let command = try CreateReadmeCommand.parse(["Sources/", "-r", "-p", "/repo"])

        #expect(command.directory == "Sources/")
        #expect(command.recursive)
        #expect(command.options.path == "/repo")
        #expect(TreeDocsMain.rewrittenArguments(["treedocs", "createREADME", "Sources/"]) == [
            "createREADME",
            "Sources/",
        ])
    }
}

private func createReadmeState(
    projectName: String = "Example",
    tree: [String: TreeEntry]
) -> TreedocsFile {
    TreedocsFile(
        project: ProjectMetadata(
            name: projectName,
            version: "0.0.0",
            lastUpdated: "2026-08-30"
        ),
        signature: TreeSignature.make(from: []),
        tree: tree
    )
}
