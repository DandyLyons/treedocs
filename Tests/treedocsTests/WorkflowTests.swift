import Testing
import PathKit
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
        #expect(TreeOperations.entry(at: "README.md", in: synced.tree)?.description == "Project readme")
        #expect(TreeOperations.entry(at: "Sources", in: synced.tree)?.description == "Source files")
        #expect(TreeOperations.entry(at: "Sources/App.swift", in: synced.tree)?.description == "Application entry point")
        try TreedocsSchemaValidator().validateFile(at: workspace.root + Path("treedocs.yaml"))
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

        var state = try workspace.loadState()
        state.signature = "not-a-valid-signature"
        try workspace.saveState(state)
        try workspace.remove("Removed.swift")

        let report = try service.check(at: workspace.root.string)
        #expect(report.schemaErrors.contains { $0.contains("signature") })
        #expect(report.extraPaths == ["Removed.swift"])
        #expect(report.missingDescriptions.contains("README.md"))
        #expect(report.hasIssues)
        #expect(report.shouldFail)
        #expect(CheckCommand.nextSteps(for: report).contains("Run `treedocs sync` to reconcile filesystem changes, refresh the stored signature, and repair generated schema state."))
        #expect(CheckCommand.nextSteps(for: report).contains("Add missing descriptions with `treedocs update <path> --description \"...\"`, or edit `treedocs.yaml` directly."))
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
        #expect(errorOutput.contains("\u{001B}[1;33mWarning: treedocs discrepancies found. Run `treedocs check` for the full diagnostic report.\u{001B}[0m"))
        #expect(errorOutput.contains("\u{001B}[1;31mfoo/\u{001B}[0m"))
        #expect(errorOutput.contains("└── \u{001B}[1;31mbar.txt\u{001B}[0m"))

        var state = try workspace.loadState()
        state.overrides = TreedocsConfig(checkSeverity: .warn)
        try workspace.saveState(state)

        let warningOutput = try service.show(at: workspace.root.string, path: ".", checkFirst: true)
        #expect(warningOutput.contains("\u{001B}[1;33mfoo/\u{001B}[0m"))
        #expect(warningOutput.contains("└── \u{001B}[1;33mbar.txt\u{001B}[0m"))
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
        #expect(rendered.contains("\u{001B}[1;32m.\u{001B}[0m"))
        #expect(rendered.contains("├── \u{001B}[1;33mdocs/\u{001B}[0m"))
        #expect(rendered.contains("│   └── \u{001B}[1;32marchitecture/\u{001B}[0m [link->src/api]"))
        #expect(rendered.contains("    └── \u{001B}[1;32mapi/\u{001B}[0m [ref]"))
        #expect(rendered.contains("REST endpoint d..."))

        let errorRendered = try TreeRenderer().render(
            tree: ["Missing.md": TreeEntry(description: nil)],
            subtreePath: nil,
            config: .defaults
        )
        #expect(errorRendered.contains("└── \u{001B}[1;31mMissing.md\u{001B}[0m"))

        let path = try service.findPath(at: workspace.root.string, query: "endpoint")
        #expect(path == "src/api")
        let missing = try service.findPath(at: workspace.root.string, query: "missing")
        #expect(missing == nil)
    }

    @Test
    func `Tree renderer formats root connectors colors metadata and descriptions exactly`() throws {
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
        \u{001B}[1;32m.\u{001B}[0m
        ├── \u{001B}[1;32mdocs/\u{001B}[0m  Documentation
        │   ├── \u{001B}[1;32mguide.md\u{001B}[0m [ref]  User guide
        │   └── \u{001B}[1;31mmissing.md\u{001B}[0m
        └── \u{001B}[1;32msrc/\u{001B}[0m  Source
            ├── \u{001B}[1;32mapi/\u{001B}[0m [link->docs/guide.md]  API
            └── \u{001B}[1;32mmain.swift\u{001B}[0m  Application entry point
        """)
    }

    @Test
    func `Tree renderer formats requested directory subtree exactly`() throws {
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
        \u{001B}[1;32msrc/\u{001B}[0m  Source
        ├── \u{001B}[1;32mComponents/\u{001B}[0m  UI components
        │   └── \u{001B}[1;32mButton.swift\u{001B}[0m  Reusable button
        └── \u{001B}[1;32mmain.swift\u{001B}[0m  Application entry point
        """)
    }

    @Test
    func `Show warns on validation issues and renders requested subtree`() throws {
        let workspace = try TestWorkspace()
        let service = try workspace.service()
        try workspace.writeFile("Sources/App.swift", contents: "print(\"hi\")")
        _ = try service.initialize(at: workspace.root.string, force: false)

        try workspace.writeFile("Sources/New.swift", contents: "print(\"new\")")

        let checkedOutput = try service.show(at: workspace.root.string, path: "Sources", checkFirst: true)
        #expect(checkedOutput.contains("Warning: this subtree has treedocs discrepancies"))
        #expect(checkedOutput.contains("App.swift"))
        #expect(checkedOutput.contains("\u{001B}[1;31mNew.swift\u{001B}[0m"))

        let uncheckedOutput = try service.show(at: workspace.root.string, path: "Sources", checkFirst: false)
        #expect(!uncheckedOutput.contains("treedocs discrepancies"))
        #expect(uncheckedOutput.contains("App.swift"))
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

        #expect(output.contains("\u{001B}[32mNo drift.\u{001B}[0m"))
        #expect(output.contains("README.md"))
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
        #expect(prompt.contains("DOCS/treedocs.schema.json"))
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
}
