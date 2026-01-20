import Foundation

public struct GitIndexSnapshot: Sendable {
    public let entries: [IndexEntry]
    public let entriesByPath: [String: IndexEntry]
    public let conflictedPaths: Set<String>
    public let entryCount: Int

    public var hasConflicts: Bool {
        !conflictedPaths.isEmpty
    }

    public init(entries: [IndexEntry]) {
        self.entries = entries
        self.entryCount = entries.count

        // Detect duplicates (conflicts in index)
        var tempDict: [String: IndexEntry] = [:]
        var conflicts: Set<String> = []

        for entry in entries {
            if tempDict[entry.path] != nil {
                // Duplicate path = corrupted/conflicted index
                conflicts.insert(entry.path)
            }
            tempDict[entry.path] = entry
        }

        self.entriesByPath = tempDict
        self.conflictedPaths = conflicts
    }
}
