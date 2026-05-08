import Testing
@testable import treedocs

@Suite("IgnoreMatcher")
struct IgnoreMatcherTests {
    @Test("Standard excluded directories are always ignored")
    func standardExcludes() {
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

    @Test("Standard excludes work for nested paths")
    func standardExcludesNested() {
        let matcher = IgnoreMatcher(patterns: [])

        #expect(matcher.shouldIgnore(relativePath: "src/.git", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "lib/node_modules/pkg", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "pkg/.build/output", isDirectory: true))
    }

    @Test("Empty path is never ignored")
    func emptyPathNotIgnored() {
        let matcher = IgnoreMatcher(patterns: [""])
        #expect(!matcher.shouldIgnore(relativePath: "", isDirectory: true))
        #expect(!matcher.shouldIgnore(relativePath: "", isDirectory: false))
    }

    @Test("Exact basename match ignores file")
    func exactBasenameMatch() {
        let matcher = IgnoreMatcher(patterns: ["notes.log"])
        #expect(matcher.shouldIgnore(relativePath: "notes.log", isDirectory: false))
        #expect(matcher.shouldIgnore(relativePath: "src/notes.log", isDirectory: false))
    }

    @Test("Exact basename match ignores directory")
    func exactBasenameMatchDirectory() {
        let matcher = IgnoreMatcher(patterns: ["tmp"])
        #expect(matcher.shouldIgnore(relativePath: "tmp", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "build/tmp", isDirectory: true))
    }

    @Test("Anchored pattern matches from root only")
    func anchoredPattern() {
        let matcher = IgnoreMatcher(patterns: ["/build"])
        #expect(matcher.shouldIgnore(relativePath: "build", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "build/output", isDirectory: true))
        #expect(!matcher.shouldIgnore(relativePath: "src/build", isDirectory: true))
    }

    @Test("Directory-only pattern ignores only directories")
    func directoryOnlyPattern() {
        let matcher = IgnoreMatcher(patterns: ["build/"])
        #expect(matcher.shouldIgnore(relativePath: "build", isDirectory: true))
        #expect(!matcher.shouldIgnore(relativePath: "build", isDirectory: false))
        #expect(matcher.shouldIgnore(relativePath: "src/build", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "src/build/output.o", isDirectory: false))
    }

    @Test("Glob pattern with asterisk matches files")
    func globAsterisk() {
        let matcher = IgnoreMatcher(patterns: ["*.log"])
        #expect(matcher.shouldIgnore(relativePath: "app.log", isDirectory: false))
        #expect(matcher.shouldIgnore(relativePath: "src/app.log", isDirectory: false))
        #expect(!matcher.shouldIgnore(relativePath: "app.txt", isDirectory: false))
    }

    @Test("Glob pattern matches directories")
    func globMatchesDirectories() {
        let matcher = IgnoreMatcher(patterns: ["*.tmp"])
        #expect(matcher.shouldIgnore(relativePath: "cache.tmp", isDirectory: true))
        #expect(!matcher.shouldIgnore(relativePath: "cache.dat", isDirectory: true))
    }

    @Test("Question mark glob matches single character")
    func questionMarkGlob() {
        let matcher = IgnoreMatcher(patterns: ["file?.txt"])
        #expect(matcher.shouldIgnore(relativePath: "file1.txt", isDirectory: false))
        #expect(matcher.shouldIgnore(relativePath: "fileA.txt", isDirectory: false))
        #expect(!matcher.shouldIgnore(relativePath: "file12.txt", isDirectory: false))
    }

    @Test("Negation pattern never ignores")
    func negationPattern() {
        let matcher = IgnoreMatcher(patterns: ["!important"])
        #expect(!matcher.shouldIgnore(relativePath: "important", isDirectory: false))
        #expect(!matcher.shouldIgnore(relativePath: "src/important", isDirectory: false))
    }

    @Test("Pattern with slash matches nested paths")
    func patternWithSlash() {
        let matcher = IgnoreMatcher(patterns: ["build/output"])
        #expect(matcher.shouldIgnore(relativePath: "build/output", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "build/output/file.o", isDirectory: false))
        #expect(matcher.shouldIgnore(relativePath: "src/build/output", isDirectory: true))
    }

    @Test("Multiple patterns combine correctly")
    func multiplePatterns() {
        let matcher = IgnoreMatcher(patterns: ["*.log", "tmp/", "build/"])
        #expect(matcher.shouldIgnore(relativePath: "app.log", isDirectory: false))
        #expect(matcher.shouldIgnore(relativePath: "tmp", isDirectory: true))
        #expect(matcher.shouldIgnore(relativePath: "build", isDirectory: true))
        #expect(!matcher.shouldIgnore(relativePath: "src/main.swift", isDirectory: false))
    }

    @Test("Non-matching path is not ignored")
    func nonMatchingNotIgnored() {
        let matcher = IgnoreMatcher(patterns: ["*.log", "tmp"])
        #expect(!matcher.shouldIgnore(relativePath: "src/main.swift", isDirectory: false))
        #expect(!matcher.shouldIgnore(relativePath: "README.md", isDirectory: false))
        #expect(!matcher.shouldIgnore(relativePath: "Sources", isDirectory: true))
    }

    @Test("Whitespace-only pattern is ignored")
    func whitespacePatternIgnored() {
        let matcher = IgnoreMatcher(patterns: ["  ", "\t"])
        #expect(!matcher.shouldIgnore(relativePath: "anything", isDirectory: false))
    }

    @Test("Anchored pattern with glob")
    func anchoredGlobPattern() {
        let matcher = IgnoreMatcher(patterns: ["/build/*.o"])
        #expect(matcher.shouldIgnore(relativePath: "build/main.o", isDirectory: false))
        #expect(!matcher.shouldIgnore(relativePath: "src/build/main.o", isDirectory: false))
    }
}
