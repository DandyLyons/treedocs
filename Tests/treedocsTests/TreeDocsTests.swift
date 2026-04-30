import Testing
import Foundation
import PathKit
import Yams

@Suite("TreeDocs Tests")
struct TreeDocsTests {
    @Test("PathKit can resolve current directory")
    func pathKitResolvesCurrentDirectory() {
        let current = Path.current
        #expect(current.exists)
    }

    @Test("Yams can round-trip a simple mapping")
    func yamsRoundTrip() throws {
        let original: [String: String] = ["key": "value"]
        let yaml = try Yams.dump(object: original)
        let parsed = try Yams.load(yaml: yaml) as? [String: String]
        #expect(parsed == original)
    }
}
