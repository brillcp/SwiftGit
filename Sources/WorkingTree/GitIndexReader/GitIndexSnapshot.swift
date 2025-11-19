import Foundation

public struct GitIndexSnapshot: Sendable {
    public let entries: [IndexEntry]
    public let entriesByPath: [String: IndexEntry]
    public let version: Int
    public let entryCount: Int
    
    public init(entries: [IndexEntry], version: Int) {
        self.entries = entries
        self.entriesByPath = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0) })
        self.version = version
        self.entryCount = entries.count
    }
    
    public subscript(path: String) -> IndexEntry? {
        entriesByPath[path]
    }
}
