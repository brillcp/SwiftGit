import Foundation

public protocol DiffGeneratorProtocol: Actor {
    func generateHunks(
        oldContent: String,
        newContent: String,
    ) async throws -> [DiffHunk]
}

// MARK: -
public actor DiffGenerator {
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
extension DiffGenerator: DiffGeneratorProtocol {
    public func generateHunks(
        oldContent: String,
        newContent: String,
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
        
        // Split into lines (keep as Substring for memory efficiency)
        let oldLines = oldContent.split(separator: "\n", omittingEmptySubsequences: false)
        let newLines = newContent.split(separator: "\n", omittingEmptySubsequences: false)
        
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
private extension DiffGenerator {
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
    func makeDiff(oldLines: [Substring], newLines: [Substring]) -> [DiffLine] {
        // Convert to arrays for difference (still views, not copies)
        let oldArray = Array(oldLines)
        let newArray = Array(newLines)
        
        // Use Swift's built-in Myers' algorithm
        let difference = newArray.difference(from: oldArray)
        
        var results: [DiffLine] = []
        var lineId = 0
        var oldIndex = 0
        var newIndex = 0
        
        // Build a map of changes for efficient lookup
        var removals: [Int: Substring] = [:]
        var insertions: [Int: Substring] = [:]
        
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
                        segments: [Segment(id: 0, text: String(oldLine), isHighlighted: false)]
                    ))
                    lineId += 1
                    results.append(DiffLine(
                        id: lineId,
                        type: .added,
                        segments: [Segment(id: 0, text: String(newLine), isHighlighted: false)]
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
                    segments: [Segment(id: 0, text: String(oldLines[oldIndex]), isHighlighted: false)]
                ))
                lineId += 1
                oldIndex += 1
            } else if isInserted {
                // Added line
                results.append(DiffLine(
                    id: lineId,
                    type: .added,
                    segments: [Segment(id: 0, text: String(newLines[newIndex]), isHighlighted: false)]
                ))
                lineId += 1
                newIndex += 1
            } else {
                // Unchanged line
                if oldIndex < oldLines.count && newIndex < newLines.count {
                    results.append(DiffLine(
                        id: lineId,
                        type: .unchanged,
                        segments: [Segment(id: 0, text: String(oldLines[oldIndex]), isHighlighted: false)]
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

                        // Remove trailing empty lines (any type)
                        while let last = currentHunk.last {
                            let isEmpty = last.segments.allSatisfy { $0.text.isEmpty }
                            
                            if isEmpty {
                                currentHunk.removeLast()
                            } else {
                                break
                            }
                        }

                        let unchangedCount = currentHunk.filter { $0.type == .unchanged }.count
                        let removedCount = currentHunk.filter { $0.type == .removed }.count
                        let addedCount = currentHunk.filter { $0.type == .added }.count
                        let oldCount = unchangedCount + removedCount
                        let newCount = unchangedCount + addedCount

                        let header = makeHunkHeader(
                            oldStart: hunkOldStart,
                            oldCount: oldCount,
                            newStart: hunkNewStart,
                            newCount: newCount
                        )
                        hunks.append(DiffHunk(id: hunkId, header: header, lines: currentHunk))
                        hunkId += 1
                        currentHunk = []
                    }
                    unchangedBuffer.removeAll()
                }
            case .added:
                if currentHunk.isEmpty {
                    hunkOldStart = oldLineNum - unchangedBuffer.suffix(contextLines).count
                    hunkNewStart = newLineNum - unchangedBuffer.suffix(contextLines).count
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
                    hunkOldStart = oldLineNum - unchangedBuffer.suffix(contextLines).count
                    hunkNewStart = newLineNum - unchangedBuffer.suffix(contextLines).count
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

            // Remove trailing empty lines (any type)
            while let last = currentHunk.last {
                let isEmpty = last.segments.allSatisfy { $0.text.isEmpty }
                
                if isEmpty {
                    currentHunk.removeLast()
                } else {
                    break
                }
            }

            let unchangedCount = currentHunk.filter { $0.type == .unchanged }.count
            let removedCount = currentHunk.filter { $0.type == .removed }.count
            let addedCount = currentHunk.filter { $0.type == .added }.count
            let oldCount = unchangedCount + removedCount
            let newCount = unchangedCount + addedCount
            
            let header = makeHunkHeader(
                oldStart: hunkOldStart,
                oldCount: oldCount,
                newStart: hunkNewStart,
                newCount: newCount
            )
            hunks.append(DiffHunk(id: hunkId, header: header, lines: currentHunk))
        }
        
        return hunks
    }
    
    /// Word-level diff using Myers' algorithm (via difference)
    func wordDiff(old: Substring, new: Substring, forOld: Bool) -> [Segment] {
        // Split into words (keep as Substring views)
        let oldWords = old.split(whereSeparator: { $0.isWhitespace })
        let newWords = new.split(whereSeparator: { $0.isWhitespace })
        
        // Use Myers' algorithm for word diff too
        let difference = Array(newWords).difference(from: Array(oldWords))
        
        var segments: [Segment] = []
        var segmentId = 0
        
        // Build change maps
        var removals = Set<Int>()
        var insertions = Set<Int>()
        
        for change in difference {
            switch change {
            case .remove(let offset, _, _):
                removals.insert(offset)
            case .insert(let offset, _, _):
                insertions.insert(offset)
            }
        }
        
        // Generate segments based on which version we're building
        if forOld {
            for (index, word) in oldWords.enumerated() {
                let isHighlighted = removals.contains(index)
                segments.append(Segment(
                    id: segmentId,
                    text: String(word),
                    isHighlighted: isHighlighted
                ))
                segmentId += 1
            }
        } else {
            for (index, word) in newWords.enumerated() {
                let isHighlighted = insertions.contains(index)
                segments.append(Segment(
                    id: segmentId,
                    text: String(word),
                    isHighlighted: isHighlighted
                ))
                segmentId += 1
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
