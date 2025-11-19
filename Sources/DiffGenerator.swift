import Foundation

public protocol DiffGeneratorProtocol: Actor {
    func generateHunks(
        oldContent: String,
        newContent: String,
        contextLines: Int
    ) async throws -> [DiffHunk]
}

// MARK: -
public actor HunkGenerator {
    private let contextLines: Int
    private let maxFileSize: Int
    private let maxLineLength: Int

    public init(
        contextLines: Int = 3,
        maxFileSize: Int = 1_000_000,  // 1MB
        maxLineLength: Int = 500       // 500 chars for word diff
    ) {
        self.contextLines = contextLines
        self.maxFileSize = maxFileSize
        self.maxLineLength = maxLineLength
    }
}

// MARK: - DiffGeneratorProtocol
extension HunkGenerator: DiffGeneratorProtocol {
    public func generateHunks(
        oldContent: String,
        newContent: String,
        contextLines: Int = 3
    ) async throws -> [DiffHunk] {
        // Early exit: identical content
        if oldContent == newContent {
            return []
        }
        
        // Early exit: both empty
        if oldContent.isEmpty && newContent.isEmpty {
            return []
        }
        
        // Size check
        guard oldContent.count <= maxFileSize else {
            throw DiffError.fileTooLarge(size: oldContent.count)
        }
        guard newContent.count <= maxFileSize else {
            throw DiffError.fileTooLarge(size: newContent.count)
        }
        
        // Binary detection
        if isBinary(oldContent) || isBinary(newContent) {
            return [makeBinaryPlaceholder()]
        }
        
        // Split into lines
        let oldLines = oldContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = newContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        
        // Generate diff
        let diff = makeDiff(oldLines: oldLines, newLines: newLines)
        
        // Group into hunks
        return groupIntoHunks(diff: diff, contextLines: contextLines)
    }
}

enum DiffError: Error, CustomStringConvertible {
    case fileTooLarge(size: Int)
    case binaryFile
    case invalidEncoding
    case emptyContent
    
    var description: String {
        switch self {
        case .fileTooLarge(let size):
            return "File too large to diff: \(size) bytes (max 1MB)"
        case .binaryFile:
            return "Cannot diff binary files"
        case .invalidEncoding:
            return "File contains invalid UTF-8"
        case .emptyContent:
            return "Both files are empty"
        }
    }
}

// MARK: - Private functions
private extension HunkGenerator {
    /// Check if content is binary (contains null bytes)
    func isBinary(_ content: String) -> Bool {
        // Check first 8KB for null bytes
        let prefix = content.utf8.prefix(8192)
        return prefix.contains(0)
    }
    
    /// Create placeholder for binary files
    func makeBinaryPlaceholder() -> DiffHunk {
        DiffHunk(
            id: 0,
            header: "Binary files differ",
            lines: [
                DiffLine(
                    id: 0,
                    type: .unchanged,
                    segments: [
                        Segment(id: 0, text: "Binary files differ", isHighlighted: false)
                    ]
                )
            ]
        )
    }
    
    /// Generate line-by-line diff using Myers' algorithm
    func makeDiff(oldLines: [String], newLines: [String]) -> [DiffLine] {
        let difference = newLines.difference(from: oldLines)
        
        var results: [DiffLine] = []
        var lineId = 0
        var oldIndex = 0
        var newIndex = 0
        
        // Build a map of changes for efficient lookup
        var removals: [Int: String] = [:]
        var insertions: [Int: String] = [:]
        
        for change in difference {
            switch change {
            case .remove(let offset, let element, _):
                removals[offset] = element
            case .insert(let offset, let element, _):
                insertions[offset] = element
            }
        }
        
        // Walk through both arrays and generate diff lines
        while oldIndex < oldLines.count || newIndex < newLines.count {
            let isRemoved = removals[oldIndex] != nil
            let isInserted = insertions[newIndex] != nil
            
            if isRemoved && isInserted {
                // Modified line - check if we should do word diff
                let oldLine = oldLines[oldIndex]
                let newLine = newLines[newIndex]
                
                if oldLine.count <= maxLineLength && newLine.count <= maxLineLength {
                    // Word-level diff for reasonable line lengths
                    let oldSegments = wordDiff(old: oldLine, new: newLine, forOld: true)
                    let newSegments = wordDiff(old: oldLine, new: newLine, forOld: false)
                    results.append(DiffLine(id: lineId, type: .removed, segments: oldSegments))
                    lineId += 1
                    results.append(DiffLine(id: lineId, type: .added, segments: newSegments))
                    lineId += 1
                } else {
                    // Lines too long - simple line-level diff
                    results.append(DiffLine(
                        id: lineId,
                        type: .removed,
                        segments: [Segment(id: 0, text: oldLine, isHighlighted: false)]
                    ))
                    lineId += 1
                    results.append(DiffLine(
                        id: lineId,
                        type: .added,
                        segments: [Segment(id: 0, text: newLine, isHighlighted: false)]
                    ))
                    lineId += 1
                }
                oldIndex += 1
                newIndex += 1
            } else if isRemoved {
                // Removed line
                results.append(DiffLine(
                    id: lineId,
                    type: .removed,
                    segments: [Segment(id: 0, text: oldLines[oldIndex], isHighlighted: false)]
                ))
                lineId += 1
                oldIndex += 1
            } else if isInserted {
                // Added line
                results.append(DiffLine(
                    id: lineId,
                    type: .added,
                    segments: [Segment(id: 0, text: newLines[newIndex], isHighlighted: false)]
                ))
                lineId += 1
                newIndex += 1
            } else {
                // Unchanged line
                if oldIndex < oldLines.count && newIndex < newLines.count {
                    results.append(DiffLine(
                        id: lineId,
                        type: .unchanged,
                        segments: [Segment(id: 0, text: oldLines[oldIndex], isHighlighted: false)]
                    ))
                    lineId += 1
                    oldIndex += 1
                    newIndex += 1
                }
            }
        }
        
        return results
    }
    
    /// Group diff lines into hunks with context
    func groupIntoHunks(diff: [DiffLine], contextLines: Int) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var currentHunk: [DiffLine] = []
        var hunkOldStart = 0
        var hunkNewStart = 0
        var oldLineNum = 0
        var newLineNum = 0
        var unchangedBuffer: [DiffLine] = []
        var hunkId = 0
        
        for line in diff {
            switch line.type {
            case .unchanged:
                unchangedBuffer.append(line)
                oldLineNum += 1
                newLineNum += 1
                
                // If we have too many unchanged lines, close the current hunk
                if unchangedBuffer.count > contextLines * 2 {
                    if !currentHunk.isEmpty {
                        // Add trailing context
                        currentHunk.append(contentsOf: unchangedBuffer.prefix(contextLines))
                        let header = makeHunkHeader(
                            oldStart: hunkOldStart,
                            oldCount: oldLineNum - hunkOldStart - unchangedBuffer.count + contextLines,
                            newStart: hunkNewStart,
                            newCount: newLineNum - hunkNewStart - unchangedBuffer.count + contextLines
                        )
                        hunks.append(DiffHunk(id: hunkId, header: header, lines: currentHunk))
                        hunkId += 1
                        currentHunk = []
                    }
                    unchangedBuffer.removeAll()
                }
                
            case .added:
                if currentHunk.isEmpty {
                    hunkOldStart = oldLineNum
                    hunkNewStart = newLineNum
                    // Add leading context
                    currentHunk.append(contentsOf: unchangedBuffer.suffix(contextLines))
                } else {
                    currentHunk.append(contentsOf: unchangedBuffer)
                }
                unchangedBuffer.removeAll()
                
                currentHunk.append(line)
                newLineNum += 1
                
            case .removed:
                if currentHunk.isEmpty {
                    hunkOldStart = oldLineNum
                    hunkNewStart = newLineNum
                    // Add leading context
                    currentHunk.append(contentsOf: unchangedBuffer.suffix(contextLines))
                } else {
                    currentHunk.append(contentsOf: unchangedBuffer)
                }
                unchangedBuffer.removeAll()
                
                currentHunk.append(line)
                oldLineNum += 1
            }
        }
        
        // Close final hunk
        if !currentHunk.isEmpty {
            currentHunk.append(contentsOf: unchangedBuffer.prefix(contextLines))
            let header = makeHunkHeader(
                oldStart: hunkOldStart,
                oldCount: oldLineNum - hunkOldStart,
                newStart: hunkNewStart,
                newCount: newLineNum - hunkNewStart
            )
            hunks.append(DiffHunk(id: hunkId, header: header, lines: currentHunk))
        }
        
        return hunks
    }
    
    /// Word-level diff for a single line
    func wordDiff(old: String, new: String, forOld: Bool) -> [Segment] {
        let oldWords = old.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let newWords = new.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        
        let lcs = longestCommonSubsequence(oldWords, newWords)
        var segments: [Segment] = []
        var segmentId = 0
        var i = 0, j = 0, lcsIndex = 0
        
        while (forOld && i < oldWords.count) || (!forOld && j < newWords.count) {
            if lcsIndex < lcs.count {
                if forOld && i < oldWords.count && oldWords[i] == lcs[lcsIndex] {
                    // Common word in old line
                    segments.append(Segment(id: segmentId, text: oldWords[i], isHighlighted: false))
                    segmentId += 1
                    i += 1
                    lcsIndex += 1
                } else if !forOld && j < newWords.count && newWords[j] == lcs[lcsIndex] {
                    // Common word in new line
                    segments.append(Segment(id: segmentId, text: newWords[j], isHighlighted: false))
                    segmentId += 1
                    j += 1
                    lcsIndex += 1
                } else {
                    // Changed/removed/added word
                    if forOld && i < oldWords.count {
                        segments.append(Segment(id: segmentId, text: oldWords[i], isHighlighted: true))
                        segmentId += 1
                        i += 1
                    } else if !forOld && j < newWords.count {
                        segments.append(Segment(id: segmentId, text: newWords[j], isHighlighted: true))
                        segmentId += 1
                        j += 1
                    }
                }
            } else {
                // Past LCS, everything is changed
                if forOld && i < oldWords.count {
                    segments.append(Segment(id: segmentId, text: oldWords[i], isHighlighted: true))
                    segmentId += 1
                    i += 1
                } else if !forOld && j < newWords.count {
                    segments.append(Segment(id: segmentId, text: newWords[j], isHighlighted: true))
                    segmentId += 1
                    j += 1
                }
            }
        }
        
        // Add spaces between words
        return segments.enumerated().map { index, segment in
            Segment(
                id: segment.id,
                text: index < segments.count - 1 ? segment.text + " " : segment.text,
                isHighlighted: segment.isHighlighted
            )
        }
    }
    
    /// Longest Common Subsequence algorithm
    func longestCommonSubsequence<T: Equatable>(_ a: [T], _ b: [T]) -> [T] {
        let m = a.count
        let n = b.count
        
        // Handle empty arrays
        if m == 0 || n == 0 {
            return []
        }
        
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        
        for i in 1...m {
            for j in 1...n {
                if a[i-1] == b[j-1] {
                    dp[i][j] = dp[i-1][j-1] + 1
                } else {
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])
                }
            }
        }
        
        // Backtrack to find the LCS
        var lcs: [T] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i-1] == b[j-1] {
                lcs.insert(a[i-1], at: 0)
                i -= 1
                j -= 1
            } else if dp[i-1][j] > dp[i][j-1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return lcs
    }
    
    /// Generate hunk header string
    func makeHunkHeader(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) -> String {
        "@@ -\(oldStart+1),\(oldCount) +\(newStart+1),\(newCount) @@"
    }
}
