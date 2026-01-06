import Foundation

public struct GitIndexSnapshot: Sendable {
    public let entries: [IndexEntry]
    public let entriesByPath: [String: IndexEntry]
    public let version: Int
    public let entryCount: Int
    
    public init(entries: [IndexEntry], version: Int) throws {
        self.entries = entries
        self.version = version
        self.entryCount = entries.count
        
        // Detect duplicates (conflicts in index)
        var tempDict: [String: IndexEntry] = [:]
        
        for entry in entries {
            if tempDict[entry.path] != nil {
                // Duplicate path = corrupted/conflicted index
                throw GitIndexError.corruptedIndex
            }
            tempDict[entry.path] = entry
        }
        
        self.entriesByPath = tempDict
    }
    
    public subscript(path: String) -> IndexEntry? {
        entriesByPath[path]
    }
}
