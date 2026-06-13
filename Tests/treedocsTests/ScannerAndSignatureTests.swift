import Testing
@testable import treedocs

@Suite("Scanner and Signature")
struct ScannerAndSignatureTests {
    @Test
    func `Scanner respects standard excludes, .gitignore, and .treedocs ignore files`() throws {
        let workspace = try TestWorkspace()
        try workspace.createDirectory("Sources")
        try workspace.writeFile("Sources/App.swift", contents: "print(\"ok\")")
        try workspace.createDirectory("node_modules")
        try workspace.writeFile("node_modules/ignored.js", contents: "")
        try workspace.writeFile("notes.log", contents: "")
        try workspace.createDirectory(".treedocs")
        try workspace.writeFile(".treedocs/.treedocs_ignore", contents: "tmp\n")
        try workspace.writeFile(".gitignore", contents: "*.log\n")
        try workspace.writeFile("tmp", contents: "")

        let loaded = try ConfigLoader(globalConfigPath: nil).load(root: workspace.root, stateOverrides: nil)
        let scan = try TreeScanner().scan(root: workspace.root, ignoreMatcher: IgnoreMatcher(patterns: loaded.ignorePatterns))

        let paths = Set(scan.normalizedPaths)
        #expect(paths.contains("Sources/"))
        #expect(paths.contains("Sources/App.swift"))
        #expect(!paths.contains("node_modules/"))
        #expect(!paths.contains("notes.log"))
        #expect(!paths.contains("tmp"))
        #expect(!paths.contains(".treedocs/"))
        #expect(TreeOperations.entry(at: "Sources", in: scan.tree)?.description == "")
        #expect(TreeOperations.entry(at: "Sources/App.swift", in: scan.tree)?.description == "")
    }

    @Test
    func `Ignore matcher supports negated patterns after broader excludes`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile(".gitignore", contents: """
        *.log
        !keep.log
        """)
        try workspace.writeFile("drop.log", contents: "")
        try workspace.writeFile("keep.log", contents: "")

        let loaded = try ConfigLoader(globalConfigPath: nil).load(root: workspace.root, stateOverrides: nil)
        let scan = try TreeScanner().scan(root: workspace.root, ignoreMatcher: IgnoreMatcher(patterns: loaded.ignorePatterns))
        let paths = Set(scan.normalizedPaths)

        #expect(!paths.contains("drop.log"))
        #expect(paths.contains("keep.log"))
    }

    @Test
    func `Scanner includes empty directories and deep nested files`() throws {
        let workspace = try TestWorkspace()
        try workspace.createDirectory("Sources/Empty")
        try workspace.writeFile("Sources/Feature/Subfeature/File.swift", contents: "")

        let scan = try TreeScanner().scan(root: workspace.root, ignoreMatcher: IgnoreMatcher(patterns: []))
        let paths = Set(scan.normalizedPaths)

        #expect(paths.contains("Sources/"))
        #expect(paths.contains("Sources/Empty/"))
        #expect(paths.contains("Sources/Feature/"))
        #expect(paths.contains("Sources/Feature/Subfeature/"))
        #expect(paths.contains("Sources/Feature/Subfeature/File.swift"))
        #expect(TreeOperations.entry(at: "Sources/Empty", in: scan.tree)?.isDirectory == true)
        #expect(TreeOperations.entry(at: "Sources/Feature/Subfeature/File.swift", in: scan.tree)?.isDirectory == false)
    }

    @Test
    func `Scanner stops at nested treedocs boundaries`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("README.md", contents: "")
        try workspace.writeFile("Vendor/Plugin/treedocs.yaml", contents: "project:\n  name: plugin\ntree: {}")
        try workspace.writeFile("Vendor/Plugin/Sources/Plugin.swift", contents: "")
        try workspace.writeFile("Vendor/Plugin/README.md", contents: "")
        try workspace.writeFile("Vendor/Other/Package.swift", contents: "")

        let scan = try TreeScanner().scan(root: workspace.root, ignoreMatcher: IgnoreMatcher(patterns: []))
        let paths = Set(scan.normalizedPaths)
        let delegatedEntry = try #require(TreeOperations.entry(at: "Vendor/Plugin", in: scan.tree))

        #expect(paths.contains("README.md"))
        #expect(paths.contains("Vendor/"))
        #expect(paths.contains("Vendor/Plugin/"))
        #expect(paths.contains("Vendor/Other/"))
        #expect(paths.contains("Vendor/Other/Package.swift"))
        #expect(!paths.contains("Vendor/Plugin/treedocs.yaml"))
        #expect(!paths.contains("Vendor/Plugin/Sources/"))
        #expect(!paths.contains("Vendor/Plugin/Sources/Plugin.swift"))
        #expect(!paths.contains("Vendor/Plugin/README.md"))
        #expect(scan.nestedBoundaries == ["Vendor/Plugin"])
        #expect(delegatedEntry.isDirectory)
        #expect(delegatedEntry.children.isEmpty)
    }

    @Test
    func `Signature is deterministic and changes on structural updates`() throws {
        let workspace = try TestWorkspace()
        try workspace.writeFile("README.md", contents: "Hello")
        try workspace.createDirectory("Sources")
        try workspace.writeFile("Sources/App.swift", contents: "print(\"ok\")")

        let scan1 = try TreeScanner().scan(root: workspace.root, ignoreMatcher: IgnoreMatcher(patterns: []))
        let scan2 = try TreeScanner().scan(root: workspace.root, ignoreMatcher: IgnoreMatcher(patterns: []))
        #expect(scan1.signature == scan2.signature)

        try workspace.writeFile("Sources/New.swift", contents: "print(\"new\")")
        let scan3 = try TreeScanner().scan(root: workspace.root, ignoreMatcher: IgnoreMatcher(patterns: []))
        #expect(scan3.signature != scan1.signature)

        try workspace.remove("Sources/New.swift")
        try workspace.writeFile("Sources/Renamed.swift", contents: "print(\"renamed\")")
        let scan4 = try TreeScanner().scan(root: workspace.root, ignoreMatcher: IgnoreMatcher(patterns: []))
        #expect(scan4.signature != scan1.signature)
    }
}
