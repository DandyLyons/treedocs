import Testing
import Foundation
import PathKit
import Yams

@Suite("TreeDocs Tests")
struct TreeDocsTests {
    @Test
    func `PathKit can resolve current directory`() {
        let current = Path.current
        #expect(current.exists)
    }

    @Test
    func `Yams can round-trip a simple mapping`() throws {
        let original: [String: String] = ["key": "value"]
        let yaml = try Yams.dump(object: original)
        let parsed = try Yams.load(yaml: yaml) as? [String: String]
        #expect(parsed == original)
    }
}
