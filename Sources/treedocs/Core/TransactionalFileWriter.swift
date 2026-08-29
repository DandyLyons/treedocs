import Foundation
import PathKit

/// One revision-checked text replacement in a multi-file transaction.
struct PlannedTextFileWrite {
    let path: Path
    let expectedSource: String
    let updatedSource: String
}

protocol TransactionalFileWriting {
    func write(_ writes: [PlannedTextFileWrite]) throws
}

/// Applies atomic per-file replacements with snapshot verification and rollback.
struct TransactionalFileWriter: TransactionalFileWriting {
    private let replace: (String, Path) throws -> Void

    init(replace: @escaping (String, Path) throws -> Void = { source, path in
        try source.write(to: path.url, atomically: true, encoding: .utf8)
    }) {
        self.replace = replace
    }

    func write(_ writes: [PlannedTextFileWrite]) throws {
        let changedWrites = writes.filter { $0.expectedSource != $0.updatedSource }
        for write in changedWrites {
            let latest: String = try write.path.read()
            guard latest == write.expectedSource else {
                throw TreeDocsError.message("File changed during README reconciliation: \(write.path.string). Retry the command.")
            }
        }

        var completed: [PlannedTextFileWrite] = []
        do {
            for write in changedWrites {
                try replace(write.updatedSource, write.path)
                completed.append(write)
            }
        } catch {
            var rollbackFailures: [String] = []
            for write in completed.reversed() {
                do {
                    try replace(write.expectedSource, write.path)
                } catch {
                    rollbackFailures.append(write.path.string)
                }
            }
            let rollbackSuffix = rollbackFailures.isEmpty
                ? "All earlier writes were rolled back."
                : "Rollback failed for: \(rollbackFailures.joined(separator: ", "))."
            throw TreeDocsError.message("README reconciliation write failed: \(error.localizedDescription) \(rollbackSuffix)")
        }
    }
}
