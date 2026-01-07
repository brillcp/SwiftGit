import Foundation

public struct GitIndexSnapshot: Sendable {
    public let entries: [IndexEntry]
    public let entriesByPath: [String: IndexEntry]
    public let conflictedPaths: [String]
    public let version: Int
    public let entryCount: Int
    
    public var hasConflicts: Bool {
        !conflictedPaths.isEmpty
    }

    public init(entries: [IndexEntry], version: Int) {
        self.entries = entries
        self.version = version
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
        self.conflictedPaths = Array(conflicts).sorted()
    }
    
    public subscript(path: String) -> IndexEntry? {
        entriesByPath[path]
    }
}
