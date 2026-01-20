import Foundation

public struct GitIndexSnapshot: Sendable {
    public let entriesByPath: [String: IndexEntry]
    public let conflictedPaths: Set<String>
    public let entryCount: Int

    public init(entries: [IndexEntry]) {
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
        self.entryCount = tempDict.count
        self.conflictedPaths = conflicts
    }
}
