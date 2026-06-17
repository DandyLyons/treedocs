import Testing
import PathKit
import Rainbow
@testable import treedocs

@Suite("Workflow", .serialized)
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

        let result = try service.syncResult(at: workspace.root.string, interactive: false)
        #expect(!result.signatureUnchanged)
        #expect(result.changes.addedPaths == ["Sources/New.swift"])
        #expect(result.changes.removedPaths == ["Sources/App.swift"])
        #expect(result.changes.changedTypePaths.isEmpty)
        withRainbowConsoleOutput {
            #expect(SyncCommand.changeSummaryMessages(for: result.changes) == [
                "Changes found:".blue,
                "\("+".green) Added: 1 (Sources/New.swift)",
                "\("-".red) Removed: 1 (Sources/App.swift)",
            ])
        }
        #expect(TreeOperations.entry(at: "README.md", in: result.file.tree)?.description == "Project readme")
        #expect(TreeOperations.entry(at: "Sources/New.swift", in: result.file.tree)?.description == "")
        #expect(TreeOperations.entry(at: "Sources/App.swift", in: result.file.tree) == nil)
    }

    @Test
    func `Init supports empty projects and nested documentation boundaries`() throws {
        let emptyWorkspace = try TestWorkspace()
        let emptyState = try emptyWorkspace.service().initialize(at: emptyWorkspace.root.string, force: false)
        #expect(emptyState.tree.isEmpty)
        #expect(emptyState.project.name == emptyWorkspace.root.lastComponent)
        #expect(emptyState.signature?.hasPrefix("sha256:") == true)
        try TreedocsSchemaValidator().validateFile(at: emptyWorkspace.root + Path("treedocs.yaml"))

        let nestedWorkspace = try TestWorkspace()
        let nestedService = try nestedWorkspace.service()
        try nestedWorkspace.writeFile("README.md", contents: "# Demo")
        try nestedWorkspace.writeFile("Vendor/Plugin/treedocs.yaml", contents: "project:\n  name: plugin\ntree: {}")
        try nestedWorkspace.writeFile("Vendor/Plugin/Sources/Plugin.swift", contents: "print(\"plugin\")")

        let nestedState = try nestedService.initialize(at: nestedWorkspace.root.string, force: false)
        let delegatedEntry = try #require(TreeOperations.entry(at: "Vendor/Plugin", in: nestedState.tree))
        #expect(delegatedEntry.isDirectory)
        #expect(delegatedEntry.children.isEmpty)
        #expect(TreeOperations.entry(at: "Vendor/Plugin/Sources/Plugin.swift", in: nestedState.tree) == nil)
        try TreedocsSchemaValidator().validateFile(at: nestedWorkspace.root + Path("treedocs.yaml"))
    }

    @Test
    func `Interactive sync preserves already documented entries`() throws {
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

        let collector = StubMissingDescriptionCollector(result: .save([:]))
        let synced = try service.sync(
            at: workspace.root.string,
            interactive: true,
            missingDescriptionCollector: collector
        )
        #expect(TreeOperations.entry(at: "README.md", in: synced.tree)?.description == "Project readme")
        #expect(collector.requestedPaths.isEmpty)
    }

    @Test
    func `Interactive sync applies entered descriptions in one save`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")
        try workspace.writeFile("Sources/App.swift", contents: "print(\"hi\")")
        _ = try service.initialize(at: workspace.root.string, force: false)

        let collector = StubMissingDescriptionCollector(result: .save([
            "README.md": " Project readme ",
            "Sources": "Source files",
            "Sources/App.swift": "Application entry point",
        ]))
        let synced = try service.sync(
            at: workspace.root.string,
            interactive: true,
            missingDescriptionCollector: collector
        )

        #expect(collector.requestedPaths == ["README.md", "Sources", "Sources/App.swift"])
        #expect(collector.requestedCandidates.first { $0.path == "README.md" }?.suggestedDescription == "Project overview, setup instructions, and usage documentation.")
        #expect(collector.requestedCandidates.first { $0.path == "Sources" }?.suggestedDescription == "Swift package source code.")
        #expect(collector.requestedCandidates.first { $0.path == "Sources/App.swift" }?.suggestedDescription == nil)
        #expect(TreeOperations.entry(at: "README.md", in: synced.tree)?.description == "Project readme")
        #expect(TreeOperations.entry(at: "Sources", in: synced.tree)?.description == "Source files")
        #expect(TreeOperations.entry(at: "Sources/App.swift", in: synced.tree)?.description == "Application entry point")
        try TreedocsSchemaValidator().validateFile(at: workspace.root + Path("treedocs.yaml"))
    }

    @Test
    func `Description suggestion catalog loads bundled YAML and matches common paths`() throws {
        let catalog = try DescriptionSuggestionCatalog.bundled()

        #expect(catalog.suggestion(for: "README.md", isDirectory: false) == "Project overview, setup instructions, and usage documentation.")
        #expect(catalog.suggestion(for: "docs/README.md", isDirectory: false) == "Project overview, setup instructions, and usage documentation.")
        #expect(catalog.suggestion(for: ".gitignore", isDirectory: false) == "Git ignore rules for generated files, local settings, and build artifacts.")
        #expect(catalog.suggestion(for: "tmp", isDirectory: true) == "Temporary files used during local development or tooling.")
        #expect(catalog.suggestion(for: "AGENTS.md", isDirectory: false) == "Repository instructions for AI coding agents.")
        #expect(catalog.suggestion(for: ".agents", isDirectory: true) == "AI agent configuration, skills, and automation resources for this repository.")
        #expect(catalog.suggestion(for: ".agents/skills", isDirectory: true) == "Reusable AI agent skills for project-specific workflows.")
        #expect(catalog.suggestion(for: ".claude", isDirectory: true) == "Claude-specific project configuration, commands, rules, and agent instructions.")
    }

    @Test
    func `Description suggestion catalog supports exact file and directory matching`() throws {
        let catalog = try DescriptionSuggestionCatalog.fromYAML("""
        paths:
          config/special.yml: Exact config file.
          generated/: Exact generated directory.
        files:
          special.yml: Generic config file.
          generated: Generated file.
        directories:
          generated/: Generated directory.
        """)

        #expect(catalog.suggestion(for: "config/special.yml", isDirectory: false) == "Exact config file.")
        #expect(catalog.suggestion(for: "other/special.yml", isDirectory: false) == "Generic config file.")
        #expect(catalog.suggestion(for: "generated", isDirectory: true) == "Exact generated directory.")
        #expect(catalog.suggestion(for: "nested/generated", isDirectory: true) == "Generated directory.")
        #expect(catalog.suggestion(for: "generated", isDirectory: false) == "Generated file.")
    }

    @Test
    func `Missing description candidates display directory paths with trailing slash`() {
        let directory = MissingDescriptionCandidate(path: "Sources", isDirectory: true, suggestedDescription: nil)
        let nestedDirectory = MissingDescriptionCandidate(path: "Sources/App", isDirectory: true, suggestedDescription: nil)
        let file = MissingDescriptionCandidate(path: "Sources/App.swift", isDirectory: false, suggestedDescription: nil)

        #expect(directory.displayPath == "Sources/")
        #expect(nestedDirectory.displayPath == "Sources/App/")
        #expect(file.displayPath == "Sources/App.swift")
    }

    @Test
    func `Interactive sync cancel does not write reconciliation or partial descriptions`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")
        _ = try service.initialize(at: workspace.root.string, force: false)
        let before = try (workspace.root + Path("treedocs.yaml")).read()

        try workspace.writeFile("New.swift", contents: "print(\"new\")")
        let collector = StubMissingDescriptionCollector(result: .cancel)
        _ = try service.sync(
            at: workspace.root.string,
            interactive: true,
            missingDescriptionCollector: collector
        )

        let after = try (workspace.root + Path("treedocs.yaml")).read()
        #expect(after == before)
        #expect(collector.requestedPaths == ["New.swift", "README.md"])
    }

    @Test
    func `Interactive sync skips blank descriptions and preserves existing metadata`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")
        try workspace.writeFile("Sources/App.swift", contents: "print(\"hi\")")
        _ = try service.initialize(at: workspace.root.string, force: false)
        _ = try service.update(
            at: workspace.root.string,
            path: "README.md",
            description: nil,
            addReferences: ["DOCS/README.md"],
            removeReferences: [],
            link: nil,
            clearLink: false
        )

        let collector = StubMissingDescriptionCollector(result: .save([
            "README.md": "Project readme",
            "Sources": "   ",
            "Sources/App.swift": "Application entry point",
        ]))
        let synced = try service.sync(
            at: workspace.root.string,
            interactive: true,
            missingDescriptionCollector: collector
        )

        #expect(TreeOperations.entry(at: "README.md", in: synced.tree)?.description == "Project readme")
        #expect(TreeOperations.entry(at: "README.md", in: synced.tree)?.references == ["DOCS/README.md"])
        #expect(TreeOperations.entry(at: "Sources", in: synced.tree)?.description == "")
        #expect(TreeOperations.entry(at: "Sources/App.swift", in: synced.tree)?.description == "Application entry point")
    }

    @Test
    func `Sync command runs interactively only for TTY contexts without opt-out`() {
        #expect(SyncCommand.shouldRunInteractively(nonInteractive: false, stdinIsTTY: true, stdoutIsTTY: true))
        #expect(!SyncCommand.shouldRunInteractively(nonInteractive: true, stdinIsTTY: true, stdoutIsTTY: true))
        #expect(!SyncCommand.shouldRunInteractively(nonInteractive: false, stdinIsTTY: false, stdoutIsTTY: true))
        #expect(!SyncCommand.shouldRunInteractively(nonInteractive: false, stdinIsTTY: true, stdoutIsTTY: false))
    }

    @Test
    func `Non-interactive sync reports remaining missing descriptions`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")
        try workspace.writeFile("Sources/App.swift", contents: "print(\"hi\")")
        _ = try service.initialize(at: workspace.root.string, force: false)

        let result = try service.syncResult(at: workspace.root.string, interactive: false)

        #expect(result.saved)
        #expect(result.signatureUnchanged)
        #expect(result.missingDescriptions == ["README.md", "Sources", "Sources/App.swift"])
        withRainbowConsoleOutput {
            #expect(SyncCommand.noChangeMessage() == "No change found.".green)
        }
        withRainbowConsoleOutput {
            #expect(SyncCommand.remainingIssueMessages(missingDescriptions: result.missingDescriptions) == [
                "Missing descriptions:".blue,
                "- README.md",
                "- Sources",
                "- Sources/App.swift",
                "Next steps:".blue,
                "- \(CheckCommand.missingDescriptionNextStep)",
            ])
        }
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
        #expect(staleReport.missingPaths == ["New.swift"])
        #expect(staleReport.shouldFail)
        #expect(CheckCommand.nextSteps(for: staleReport).contains("Run `treedocs sync` to reconcile filesystem changes, refresh the stored signature, and repair generated schema state."))

        var state = try workspace.loadState()
        state.overrides = TreedocsConfig(checkSeverity: .warn)
        try workspace.saveState(state)

        cleanReport = try service.check(at: workspace.root.string)
        #expect(cleanReport.hasIssues)
        #expect(!cleanReport.shouldFail)
        #expect(CheckCommand.nextSteps(for: cleanReport).isEmpty)
    }

    @Test
    func `Check reports schema failures extra paths and missing descriptions`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")
        try workspace.writeFile("Removed.swift", contents: "print(\"old\")")
        _ = try service.initialize(at: workspace.root.string, force: false)

        let state = try workspace.loadState()
        try workspace.writeFile("treedocs.yaml", contents: try state.toYAMLString().replacingOccurrences(
            of: state.signature ?? "",
            with: "not-a-valid-signature"
        ))
        try workspace.remove("Removed.swift")

        let report = try service.check(at: workspace.root.string)
        #expect(report.schemaErrors.contains { $0.contains("signature") })
        #expect(report.extraPaths == ["Removed.swift"])
        #expect(report.missingDescriptions.contains("README.md"))
        #expect(report.hasIssues)
        #expect(report.shouldFail)
        #expect(CheckCommand.nextSteps(for: report).contains("Run `treedocs sync` to reconcile filesystem changes, refresh the stored signature, and repair generated schema state."))
        #expect(CheckCommand.nextSteps(for: report).contains("Add missing descriptions with `treedocs update <path> \"...\"`, edit `treedocs.yaml` directly, or `treedocs sync` in interactive mode."))
    }

    @Test
    func `Check reports changed paths when filesystem kind changes`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("Sources", contents: "old file")
        _ = try service.initialize(at: workspace.root.string, force: false)

        try workspace.remove("Sources")
        try workspace.writeFile("Sources/App.swift", contents: "print(\"new directory\")")

        let report = try service.check(at: workspace.root.string)
        #expect(report.hasSignatureDrift)
        #expect(report.changedPaths == ["Sources"])
        #expect(report.missingPaths == ["Sources/App.swift"])
        #expect(report.extraPaths.isEmpty)
        #expect(report.hasIssues)
        #expect(report.shouldFail)
        #expect(CheckCommand.nextSteps(for: report).contains("Run `treedocs sync` to reconcile filesystem changes, refresh the stored signature, and repair generated schema state."))
    }

    @Test
    func `Check reports nested boundaries and parent child conflicts`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("Vendor/Plugin/treedocs.yaml", contents: "project:\n  name: plugin\ntree: {}")
        try workspace.writeFile("Vendor/Plugin/Sources/Plugin.swift", contents: "print(\"plugin\")")

        _ = try service.initialize(at: workspace.root.string, force: false)
        var state = try workspace.loadState()
        state.tree = [
            "Vendor": TreeEntry(description: "Vendor code", children: [
                "Plugin": TreeEntry(description: "Delegated plugin", children: [
                    "Sources": TreeEntry(description: "Plugin sources", children: [
                        "Plugin.swift": TreeEntry(description: "Plugin entry point"),
                    ], isDirectory: true),
                ], isDirectory: true),
            ], isDirectory: true),
        ]
        try workspace.saveState(state)

        let report = try service.check(at: workspace.root.string)
        #expect(report.nestedBoundaries == ["Vendor/Plugin"])
        #expect(report.shadowedPaths == ["Vendor/Plugin/Sources", "Vendor/Plugin/Sources/Plugin.swift"])
        #expect(report.extraPaths == ["Vendor/Plugin/Sources", "Vendor/Plugin/Sources/Plugin.swift"])
        #expect(report.hasIssues)
        #expect(report.shouldFail)
    }

    @Test
    func `Inspect resolves direct links, chained links, and cycle errors`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("README.md", contents: "demo")
        try workspace.saveState(
            TreedocsFile(
                project: ProjectMetadata(name: "Example", version: "1.0.0", lastUpdated: "2026-06-13"),
                signature: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
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
    func `Show resolves internal links and link chains to rendered targets`() throws {
        let workspace = try TestWorkspace()
        try workspace.saveState(
            TreedocsFile(
                project: ProjectMetadata(name: "Example", version: "1.0.0", lastUpdated: "2026-06-13"),
                signature: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                tree: [
                    "src": TreeEntry(description: "Source", children: [
                        "api": TreeEntry(description: "API surface", children: [
                            "Routes.swift": TreeEntry(description: "Route declarations"),
                        ], isDirectory: true),
                    ], isDirectory: true),
                    "docs": TreeEntry(children: [
                        "architecture": TreeEntry(description: "Architecture alias", link: "../src/api", isDirectory: true),
                    ], isDirectory: true),
                    "api-alias": TreeEntry(link: "docs/architecture", isDirectory: true),
                ]
            )
        )

        let service = try workspace.service()
        let direct = try service.show(at: workspace.root.string, path: "docs/architecture", checkFirst: false)
        #expect(direct.contains("src/api/"))
        #expect(direct.contains("Routes.swift"))
        #expect(!direct.contains("Architecture alias"))

        let chained = try service.show(at: workspace.root.string, path: "api-alias", checkFirst: false)
        #expect(chained.contains("src/api/"))
        #expect(chained.contains("Route declarations"))
    }

    @Test
    func `Show displays external aliases`() throws {
        let workspace = try TestWorkspace()
        try workspace.saveState(
            TreedocsFile(
                project: ProjectMetadata(name: "Example", version: "1.0.0", lastUpdated: "2026-06-13"),
                signature: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                tree: [
                    "api-docs": TreeEntry(link: "https://example.com/api"),
                ]
            )
        )

        let output = try workspace.service().show(at: workspace.root.string, path: "api-docs", checkFirst: false)
        #expect(output == "External alias: api-docs -> https://example.com/api")
    }

    @Test
    func `Show colors discrepancy warning and renders missing filesystem entries by severity`() throws {
        try withRainbowConsoleOutput {
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

        try workspace.writeFile("foo/bar.txt", contents: "new")

        let errorOutput = try service.show(at: workspace.root.string, path: ".", checkFirst: true)
        #expect(errorOutput.contains("Warning: treedocs discrepancies found. Run `treedocs check` for the full diagnostic report.".yellow.bold))
        #expect(errorOutput.contains("foo/".red.bold))
        #expect(errorOutput.contains("└── \("bar.txt".red.bold)"))

        var state = try workspace.loadState()
        state.overrides = TreedocsConfig(checkSeverity: .warn)
        try workspace.saveState(state)

        let warningOutput = try service.show(at: workspace.root.string, path: ".", checkFirst: true)
        #expect(warningOutput.contains("foo/".yellow.bold))
        #expect(warningOutput.contains("└── \("bar.txt".yellow.bold)"))
        }
    }

    @Test
    func `Show reports broken links and link cycles`() throws {
        let workspace = try TestWorkspace()
        try workspace.saveState(
            TreedocsFile(
                project: ProjectMetadata(name: "Example", version: "1.0.0", lastUpdated: "2026-06-13"),
                signature: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                tree: [
                    "broken": TreeEntry(link: "missing/target"),
                    "cycle-a": TreeEntry(link: "cycle-b"),
                    "cycle-b": TreeEntry(link: "cycle-a"),
                ]
            )
        )

        let service = try workspace.service()
        do {
            _ = try service.show(at: workspace.root.string, path: "broken", checkFirst: false)
            Issue.record("Expected broken link error")
        } catch {
            #expect(error.localizedDescription.contains("Broken link: broken -> missing/target"))
            #expect(error.localizedDescription.contains("missing target: missing/target"))
        }

        do {
            _ = try service.show(at: workspace.root.string, path: "cycle-a", checkFirst: false)
            Issue.record("Expected link cycle error")
        } catch {
            #expect(error.localizedDescription.contains("Link cycle detected: cycle-a -> cycle-b -> cycle-a"))
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
    func `Update link and clear link preserve schema-valid entries`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")
        try workspace.writeFile("Sources/App.swift", contents: "print(\"hi\")")
        _ = try service.initialize(at: workspace.root.string, force: false)

        let linked = try service.update(
            at: workspace.root.string,
            path: "README.md",
            description: nil,
            addReferences: [],
            removeReferences: [],
            link: "Sources/App.swift",
            clearLink: false
        )
        #expect(TreeOperations.entry(at: "README.md", in: linked.tree)?.link == "Sources/App.swift")
        try TreedocsSchemaValidator().validateFile(at: workspace.root + Path("treedocs.yaml"))

        let cleared = try service.update(
            at: workspace.root.string,
            path: "README.md",
            description: nil,
            addReferences: [],
            removeReferences: [],
            link: nil,
            clearLink: true
        )
        #expect(TreeOperations.entry(at: "README.md", in: cleared.tree)?.link == nil)
        try TreedocsSchemaValidator().validateFile(at: workspace.root + Path("treedocs.yaml"))
    }

    @Test
    func `Update reports missing paths without mutating state`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")
        _ = try service.initialize(at: workspace.root.string, force: false)
        let before = try (workspace.root + Path("treedocs.yaml")).read()

        do {
            _ = try service.update(
                at: workspace.root.string,
                path: "Missing.swift",
                description: "Missing file",
                addReferences: [],
                removeReferences: [],
                link: nil,
                clearLink: false
            )
            Issue.record("Expected missing path update to fail")
        } catch {
            #expect(error.localizedDescription.contains("Path not found in treedocs tree: Missing.swift"))
        }

        let after = try (workspace.root + Path("treedocs.yaml")).read()
        #expect(after == before)
    }

    @Test
    func `ls renders refs and links and path returns a raw matching path`() throws {
        try withRainbowConsoleOutput {
        let workspace = try TestWorkspace()
        try workspace.saveState(
            TreedocsFile(
                project: ProjectMetadata(name: "Example", version: "1.0.0", lastUpdated: "2026-06-13"),
                overrides: TreedocsConfig(maxDescriptionLength: 18, indentSize: 4, checkSeverity: .warn),
                signature: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
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
        #expect(rendered.contains(".".green.bold))
        #expect(rendered.contains("├── \("docs/".yellow.bold)"))
        #expect(rendered.contains("│   └── \("architecture/".green.bold) [link->src/api]"))
        #expect(rendered.contains("    └── \("api/".green.bold) [ref]"))
        #expect(rendered.contains("REST endpoint d..."))

        let errorRendered = try TreeRenderer().render(
            tree: ["Missing.md": TreeEntry(description: nil)],
            subtreePath: nil,
            config: .defaults
        )
        #expect(errorRendered.contains("└── \("Missing.md".red.bold)"))

        let path = try service.findPath(at: workspace.root.string, query: "endpoint")
        #expect(path == "src/api")
        let missing = try service.findPath(at: workspace.root.string, query: "missing")
        #expect(missing == nil)
        }
    }

    @Test
    func `Tree renderer formats root connectors colors metadata and descriptions exactly`() throws {
        try withRainbowConsoleOutput {
        let tree = [
            "docs": TreeEntry(description: "Documentation", children: [
                "guide.md": TreeEntry(description: "User guide", references: ["DOCS/GUIDE.md"]),
                "missing.md": TreeEntry(description: nil),
            ], isDirectory: true),
            "src": TreeEntry(description: "Source", children: [
                "api": TreeEntry(description: "API", link: "docs/guide.md", isDirectory: true),
                "main.swift": TreeEntry(description: "Application entry point"),
            ], isDirectory: true),
        ]

        let rendered = try TreeRenderer().render(
            tree: tree,
            subtreePath: nil,
            config: TreedocsConfig(maxDescriptionLength: 120, checkSeverity: .error)
        )

        #expect(rendered == """
        \(".".green.bold)
        ├── \("docs/".green.bold)  Documentation
        │   ├── \("guide.md".green.bold) [ref]  User guide
        │   └── \("missing.md".red.bold)
        └── \("src/".green.bold)  Source
            ├── \("api/".green.bold) [link->docs/guide.md]  API
            └── \("main.swift".green.bold)  Application entry point
        """)
        }
    }

    @Test
    func `Tree renderer formats requested directory subtree exactly`() throws {
        try withRainbowConsoleOutput {
        let tree = [
            "src": TreeEntry(description: "Source", children: [
                "Components": TreeEntry(description: "UI components", children: [
                    "Button.swift": TreeEntry(description: "Reusable button"),
                ], isDirectory: true),
                "main.swift": TreeEntry(description: "Application entry point"),
            ], isDirectory: true),
        ]

        let rendered = try TreeRenderer().render(
            tree: tree,
            subtreePath: "src",
            config: TreedocsConfig(maxDescriptionLength: 120, checkSeverity: .error)
        )

        #expect(rendered == """
        \("src/".green.bold)  Source
        ├── \("Components/".green.bold)  UI components
        │   └── \("Button.swift".green.bold)  Reusable button
        └── \("main.swift".green.bold)  Application entry point
        """)
        }
    }

    @Test
    func `Explore renders root level with header hint and collapsed directory counts`() throws {
        try withRainbowConsoleOutput {
        let tree = explorationFixtureTree()

        let rendered = try TreeRenderer().renderExploration(
            tree: tree,
            expandedPaths: [],
            config: TreedocsConfig(maxDescriptionLength: 120, checkSeverity: .error)
        )

        #expect(rendered == """
        Expand collapsed folders with `treedocs explore <subpath>`.
        \(".".green.bold)
        ├── \("Docs/".green.bold) \("(0 items)".lightBlack)  Documentation
        ├── \("README.md".green.bold)  Project readme
        ├── \("Sources/".green.bold) \("(3 items)".lightBlack)  Source files
        └── \("Tests/".green.bold) \("(1 item)".lightBlack)  Test suite
        """)
        #expect(!rendered.contains("Commands/"))
        #expect(!rendered.contains("WorkflowTests.swift"))
        }
    }

    @Test
    func `Explore expands multiple requested directories one level`() throws {
        try withRainbowConsoleOutput {
        let rendered = try TreeRenderer().renderExploration(
            tree: explorationFixtureTree(),
            expandedPaths: ["Sources", "Tests"],
            config: TreedocsConfig(maxDescriptionLength: 120, checkSeverity: .error)
        )

        #expect(rendered.contains("├── \("Sources/".green.bold)  Source files"))
        #expect(rendered.contains("│   ├── \("Support/".green.bold) \("(0 items)".lightBlack)  Shared helpers"))
        #expect(rendered.contains("│   ├── \("TreeDocs.swift".green.bold)  Entry point"))
        #expect(rendered.contains("│   └── \("treedocs/".green.bold) \("(2 items)".lightBlack)  Executable target"))
        #expect(rendered.contains("Expand collapsed folders with `treedocs explore <subpath>`."))
        #expect(!rendered.contains("run `treedocs explore Sources/treedocs` to expand"))
        #expect(rendered.contains("    └── \("WorkflowTests.swift".green.bold)  Workflow tests"))
        #expect(!rendered.contains("ExploreCommand.swift"))
        }
    }

    @Test
    func `Explore opens ancestors for deep targets and expands target one level`() throws {
        try withRainbowConsoleOutput {
        let rendered = try TreeRenderer().renderExploration(
            tree: explorationFixtureTree(),
            expandedPaths: ["Sources/treedocs/Commands"],
            config: TreedocsConfig(maxDescriptionLength: 120, checkSeverity: .error)
        )

        #expect(rendered.contains("├── \("Sources/".green.bold)  Source files"))
        #expect(rendered.contains("│   └── \("treedocs/".green.bold)  Executable target"))
        #expect(rendered.contains("│       └── \("Commands/".green.bold)  CLI commands"))
        #expect(rendered.contains("│           ├── \("ExploreCommand.swift".green.bold)  Explore command"))
        #expect(rendered.contains("│           └── \("LsCommand.swift".green.bold)  List command"))
        #expect(!rendered.contains("Support/"))
        #expect(!rendered.contains("TreeDocs.swift"))
        }
    }

    @Test
    func `Explore accepts file targets normalizes slashes and reports missing paths`() throws {
        let tree = explorationFixtureTree()
        let renderer = TreeRenderer()
        let config = TreedocsConfig(maxDescriptionLength: 120, checkSeverity: .error)

        let normalized = try renderer.renderExploration(tree: tree, expandedPaths: ["Sources/"], config: config)
        let unnormalized = try renderer.renderExploration(tree: tree, expandedPaths: ["Sources"], config: config)
        #expect(normalized == unnormalized)

        let fileTarget = try renderer.renderExploration(
            tree: tree,
            expandedPaths: ["Sources/treedocs/Commands/LsCommand.swift"],
            config: config
        )
        #expect(fileTarget.contains("LsCommand.swift"))
        #expect(!fileTarget.contains("ExploreCommand.swift"))

        do {
            _ = try renderer.renderExploration(tree: tree, expandedPaths: ["Missing"], config: config)
            Issue.record("Expected missing explore target to fail")
        } catch {
            #expect(error.localizedDescription.contains("Path not found in treedocs tree: Missing"))
        }

        #expect(TreeDocsMain.rewrittenArguments(["treedocs", "explore", "Sources"]) == ["explore", "Sources"])
    }

    @Test
    func `Show warns on validation issues and renders requested subtree`() throws {
        try withRainbowConsoleOutput {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("Sources/App.swift", contents: "print(\"hi\")")
        _ = try service.initialize(at: workspace.root.string, force: false)

        try workspace.writeFile("Sources/New.swift", contents: "print(\"new\")")

        let checkedOutput = try service.show(at: workspace.root.string, path: "Sources", checkFirst: true)
        #expect(checkedOutput.contains("Warning: this subtree has treedocs discrepancies"))
        #expect(checkedOutput.contains("App.swift"))
        #expect(checkedOutput.contains("New.swift".red.bold))

        let uncheckedOutput = try service.show(at: workspace.root.string, path: "Sources", checkFirst: false)
        #expect(!uncheckedOutput.contains("treedocs discrepancies"))
        #expect(uncheckedOutput.contains("App.swift"))
        }
    }

    @Test
    func `Show notes broader repo drift when requested subtree is current`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("Sources/App.swift", contents: "print(\"hi\")")
        _ = try service.initialize(at: workspace.root.string, force: false)
        _ = try service.update(
            at: workspace.root.string,
            path: "Sources",
            description: "Source files",
            addReferences: [],
            removeReferences: [],
            link: nil,
            clearLink: false
        )
        _ = try service.update(
            at: workspace.root.string,
            path: "Sources/App.swift",
            description: "App entry point",
            addReferences: [],
            removeReferences: [],
            link: nil,
            clearLink: false
        )

        try workspace.writeFile("foo/bar.txt", contents: "new")

        let output = try service.show(at: workspace.root.string, path: "Sources", checkFirst: true)
        #expect(output.contains("Note: treedocs has drift elsewhere in this repo; `Sources/` is current. Run `treedocs check` or `treedocs sync`."))
        #expect(!output.contains("Warning: treedocs discrepancies found"))
        #expect(!output.contains("Warning: this subtree has treedocs discrepancies"))
        #expect(!output.contains("foo/"))
        #expect(output.contains("App.swift"))
    }

    @Test
    func `Show reports no drift when checked state is clean`() throws {
        try withRainbowConsoleOutput {
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

        let output = try service.show(at: workspace.root.string, path: ".", checkFirst: true)

        #expect(output.contains("✅ The treedocs below is up to date with the filesystem.".green))
        #expect(output.contains("README.md"))
        }
    }

    @Test
    func `Bare treedocs invocation runs checked show on current directory`() throws {
        #expect(TreeDocsMain.rewrittenArguments(["treedocs"]) == ["show", "."])

        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")
        _ = try service.initialize(at: workspace.root.string, force: false)

        try workspace.writeFile("Sources/App.swift", contents: "print(\"hi\")")

        let output = try service.show(at: workspace.root.string, path: ".", checkFirst: true)
        #expect(output.contains("Warning: treedocs discrepancies found"))
        #expect(output.contains("README.md"))
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
        #expect(prompt.contains("site/schemas/0.1.0/treedocs.schema.json"))
    }

    @Test
    func `Fill prompt does not mutate treedocs state`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("README.md", contents: "# Demo")
        _ = try service.initialize(at: workspace.root.string, force: false)
        let before = try (workspace.root + Path("treedocs.yaml")).read()

        let prompt = try service.fillPrompt(at: workspace.root.string)

        let after = try (workspace.root + Path("treedocs.yaml")).read()
        #expect(prompt.contains("Ask clarifying questions for unclear paths"))
        #expect(after == before)
    }

    private func explorationFixtureTree() -> [String: TreeEntry] {
        [
            "Docs": TreeEntry(description: "Documentation", children: [:], isDirectory: true),
            "README.md": TreeEntry(description: "Project readme"),
            "Sources": TreeEntry(description: "Source files", children: [
                "Support": TreeEntry(description: "Shared helpers", children: [:], isDirectory: true),
                "TreeDocs.swift": TreeEntry(description: "Entry point"),
                "treedocs": TreeEntry(description: "Executable target", children: [
                    "Commands": TreeEntry(description: "CLI commands", children: [
                        "ExploreCommand.swift": TreeEntry(description: "Explore command"),
                        "LsCommand.swift": TreeEntry(description: "List command"),
                    ], isDirectory: true),
                    "Core": TreeEntry(description: "Core services", children: [
                        "TreeRenderer.swift": TreeEntry(description: "Tree renderer"),
                    ], isDirectory: true),
                ], isDirectory: true),
            ], isDirectory: true),
            "Tests": TreeEntry(description: "Test suite", children: [
                "WorkflowTests.swift": TreeEntry(description: "Workflow tests"),
            ], isDirectory: true),
        ]
    }
}
