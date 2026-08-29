import Foundation
import PathKit

/// One revision-checked text replacement in a multi-file transaction.
struct PlannedTextFileWrite {
    /// Destination file to replace.
    let path: Path

    /// Source snapshot that must still match immediately before any replacement begins.
    let expectedSource: String

    /// Complete replacement contents.
    let updatedSource: String
}

/// Writes a staged set of text replacements as one recoverable operation.
protocol TransactionalFileWriting {
    /// Verifies source revisions, replaces changed files, and rolls back completed replacements on failure.
    ///
    /// - Parameter writes: Complete replacement plans, including unchanged files that may be skipped.
    /// - Throws: A read, revision, replacement, or rollback error wrapped as `TreeDocsError` when appropriate.
    func write(_ writes: [PlannedTextFileWrite]) throws
}

/// Applies atomic per-file replacements with snapshot verification and rollback.
struct TransactionalFileWriter: TransactionalFileWriting {
    private let replace: (String, Path) throws -> Void

    /// Creates a writer with an injectable atomic replacement operation.
    ///
    /// - Parameter replace: Writes complete text to a destination path. The default uses Foundation's atomic write.
    init(replace: @escaping (String, Path) throws -> Void = { source, path in
        try source.write(to: path.url, atomically: true, encoding: .utf8)
    }) {
        self.replace = replace
    }

    /// Applies changed plans only after every source snapshot has been verified.
    ///
    /// Successfully replaced files are restored in reverse order if a later replacement fails.
    ///
    /// - Parameter writes: Planned source snapshots and replacement contents.
    /// - Throws: `TreeDocsError` when a source changed or a replacement fails.
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
