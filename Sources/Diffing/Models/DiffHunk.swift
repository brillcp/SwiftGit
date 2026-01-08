import Foundation

public struct DiffHunk: Hashable, Sendable {
    public let id: Int
    public let header: String
    public let lines: [DiffLine]
    public let hasNoNewlineAtEnd: Bool

    public init(id: Int, header: String, lines: [DiffLine], hasNoNewlineAtEnd: Bool = false) {
        self.id = id
        self.header = header
        self.lines = lines
        self.hasNoNewlineAtEnd = hasNoNewlineAtEnd
    }
}

public extension DiffHunk {
    func displayRows() -> [DiffLine] {
        var result: [DiffLine] = []
        var removedBuffer: [DiffLine] = []
        var addedBuffer: [DiffLine] = []
        
        func flush() {
            result.append(contentsOf: removedBuffer)  // All removed first
            result.append(contentsOf: addedBuffer)    // Then all added
            removedBuffer.removeAll()
            addedBuffer.removeAll()
        }
        
        for line in lines {
            switch line.type {
            case .unchanged:
                flush()
                result.append(line)
            case .removed:
                removedBuffer.append(line)
            case .added:
                addedBuffer.append(line)
            }
        }
        
        flush()
        return result
    }
}
