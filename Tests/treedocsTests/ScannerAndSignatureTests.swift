import Testing
@testable import treedocs

@Suite("Scanner and Signature")
struct ScannerAndSignatureTests {
    @Test("Scanner respects standard excludes, .gitignore, and .treedocs ignore files")
    func scannerIgnoresConfiguredPaths() throws {
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

    @Test("Ignore matcher supports negated patterns after broader excludes")
    func scannerSupportsNegationPatterns() throws {
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

    @Test("Signature is deterministic and changes on structural updates")
    func signatureDeterminism() throws {
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
