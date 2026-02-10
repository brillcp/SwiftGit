import Foundation
import Collections

public struct WorkingTreeStatus: Sendable {
    public let files: OrderedDictionary<String, WorkingTreeFile>
    public let conflictedFiles: Set<String>

    public init(files: OrderedDictionary<String, WorkingTreeFile>) {
        self.files = files

        let conflicted = files.values
            .filter { $0.staged == .conflicted || $0.unstaged == .conflicted }
            .map(\.path)
        conflictedFiles = Set(conflicted)
    }
}