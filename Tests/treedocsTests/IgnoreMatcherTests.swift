import Testing
@testable import treedocs

@Suite("IgnoreMatcher")
struct IgnoreMatcherTests {
    @Test
    func `Standard excluded directories are always ignored`() {
        let matcher = IgnoreMatcher(patterns: [])

        #expect(matcher.shouldIgnore(relativePath: ".git", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: ".build", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: ".swiftpm", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: ".treedocs", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: ".agents", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: ".opencode", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "node_modules", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "treedocs.yaml", isDirectory: false))
    }

    @Test
    func `Standard excludes work for nested paths`() {
        let matcher = IgnoreMatcher(patterns: [])

        #expect(matcher.shouldIgnore(relativePath: "src/.git", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "lib/node_modules/pkg", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "pkg/.build/output", isDirectory: true))
    }

    @Test
    func `Empty path is never ignored`() {
        let matcher = IgnoreMatcher(patterns: [""])
        #expect(!matcher.shouldIgnore(relativePath: "", isDirectory: true))
        #expect(!matcher.shouldIgnore(relativePath: "", isDirectory: false))
    }

    @Test
    func `Exact basename match ignores file`() {
        let matcher = IgnoreMatcher(patterns: ["notes.log"])
        #expect(matcher.shouldIgnore(relativePath: "notes.log", isDirectory: false))
        #expect(matcher.shouldIgnore(relativePath: "src/notes.log", isDirectory: false))
    }

    @Test
    func `Exact basename match ignores directory`() {
        let matcher = IgnoreMatcher(patterns: ["tmp"])
        #expect(matcher.shouldIgnore(relativePath: "tmp", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "build/tmp", isDirectory: true))
    }

    @Test
    func `Anchored pattern matches from root only`() {
        let matcher = IgnoreMatcher(patterns: ["/build"])
        #expect(matcher.shouldIgnore(relativePath: "build", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "build/output", isDirectory: true))
        #expect(!matcher.shouldIgnore(relativePath: "src/build", isDirectory: true))
    }

    @Test
    func `Directory-only pattern ignores only directories`() {
        let matcher = IgnoreMatcher(patterns: ["build/"])
        #expect(matcher.shouldIgnore(relativePath: "build", isDirectory: true))
        #expect(!matcher.shouldIgnore(relativePath: "build", isDirectory: false))
        #expect(matcher.shouldIgnore(relativePath: "src/build", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "src/build/output.o", isDirectory: false))
    }

    @Test
    func `Glob pattern with asterisk matches files`() {
        let matcher = IgnoreMatcher(patterns: ["*.log"])
        #expect(matcher.shouldIgnore(relativePath: "app.log", isDirectory: false))
        #expect(matcher.shouldIgnore(relativePath: "src/app.log", isDirectory: false))
        #expect(!matcher.shouldIgnore(relativePath: "app.txt", isDirectory: false))
    }

    @Test
    func `Glob pattern matches directories`() {
        let matcher = IgnoreMatcher(patterns: ["*.tmp"])
        #expect(matcher.shouldIgnore(relativePath: "cache.tmp", isDirectory: true))
        #expect(!matcher.shouldIgnore(relativePath: "cache.dat", isDirectory: true))
    }

    @Test
    func `Question mark glob matches single character`() {
        let matcher = IgnoreMatcher(patterns: ["file?.txt"])
        #expect(matcher.shouldIgnore(relativePath: "file1.txt", isDirectory: false))
        #expect(matcher.shouldIgnore(relativePath: "fileA.txt", isDirectory: false))
        #expect(!matcher.shouldIgnore(relativePath: "file12.txt", isDirectory: false))
    }

    @Test
    func `Negation pattern never ignores`() {
        let matcher = IgnoreMatcher(patterns: ["!important"])
        #expect(!matcher.shouldIgnore(relativePath: "important", isDirectory: false))
        #expect(!matcher.shouldIgnore(relativePath: "src/important", isDirectory: false))
    }

    @Test
    func `Pattern with slash matches nested paths`() {
        let matcher = IgnoreMatcher(patterns: ["build/output"])
        #expect(matcher.shouldIgnore(relativePath: "build/output", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "build/output/file.o", isDirectory: false))
        #expect(matcher.shouldIgnore(relativePath: "src/build/output", isDirectory: true))
    }

    @Test
    func `Multiple patterns combine correctly`() {
        let matcher = IgnoreMatcher(patterns: ["*.log", "tmp/", "build/"])
        #expect(matcher.shouldIgnore(relativePath: "app.log", isDirectory: false))
        #expect(matcher.shouldIgnore(relativePath: "tmp", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "build", isDirectory: true))
        #expect(!matcher.shouldIgnore(relativePath: "src/main.swift", isDirectory: false))
    }

    @Test
    func `Non-matching path is not ignored`() {
        let matcher = IgnoreMatcher(patterns: ["*.log", "tmp"])
        #expect(!matcher.shouldIgnore(relativePath: "src/main.swift", isDirectory: false))
        #expect(!matcher.shouldIgnore(relativePath: "README.md", isDirectory: false))
        #expect(!matcher.shouldIgnore(relativePath: "Sources", isDirectory: true))
    }

    @Test
    func `Whitespace-only pattern is ignored`() {
        let matcher = IgnoreMatcher(patterns: ["  ", "\t"])
        #expect(!matcher.shouldIgnore(relativePath: "anything", isDirectory: false))
    }

    @Test
    func `Anchored pattern with glob`() {
        let matcher = IgnoreMatcher(patterns: ["/build/*.o"])
        #expect(matcher.shouldIgnore(relativePath: "build/main.o", isDirectory: false))
        #expect(!matcher.shouldIgnore(relativePath: "src/build/main.o", isDirectory: false))
    }
}
