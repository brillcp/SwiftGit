import Foundation

public actor GitDiffParser {
    public init() {}
}

// MARK: - Public functions
extension GitDiffParser {
    /// Parse Git's diff output into DiffHunk objects
    public func parse(_ diffOutput: String) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var currentHunk: DiffHunk?
        var currentLines: [DiffLine] = []
        var lineId = 0
        var hunkId = 0

        let lines = diffOutput.split(separator: String.newLine, omittingEmptySubsequences: false)

        for line in lines {
            let lineStr = String(line)

            // Skip header lines
            if lineStr.hasPrefix("diff --git") ||
                lineStr.hasPrefix("index ") ||
                lineStr.hasPrefix("--- ") ||
                lineStr.hasPrefix("+++ ") ||
                lineStr.hasPrefix("Binary files") {
                continue
            }

            // Hunk header
            if lineStr.hasPrefix("@@ ") {
                // Save previous hunk if exists
                if let hunk = currentHunk {
                    hunks.append(DiffHunk(
                        id: hunkId,
                        header: hunk.header,
                        lines: currentLines,
                        hasNoNewlineAtEnd: hunk.hasNoNewlineAtEnd
                    ))
                    hunkId += 1
                }

                // Start new hunk
                currentHunk = DiffHunk(
                    id: hunkId,
                    header: lineStr,
                    lines: [],
                    hasNoNewlineAtEnd: false
                )
                currentLines = []
                lineId = 0
                continue
            }

            // No newline marker
            if lineStr.hasPrefix(String.noNewLine) {
                if currentHunk != nil {
                    currentHunk = DiffHunk(
                        id: currentHunk!.id,
                        header: currentHunk!.header,
                        lines: currentHunk!.lines,
                        hasNoNewlineAtEnd: true
                    )
                }
                continue
            }

            // Parse diff line
            guard !lineStr.isEmpty, currentHunk != nil else { continue }

            let type: DiffLine.LineType
            let content: String

            if lineStr.hasPrefix("+") {
                type = .added
                content = String(lineStr.dropFirst())
            } else if lineStr.hasPrefix("-") {
                type = .removed
                content = String(lineStr.dropFirst())
            } else if lineStr.hasPrefix(" ") {
                type = .unchanged
                content = String(lineStr.dropFirst())
            } else {
                continue
            }

            // Create DiffLine with single segment (no word-diff yet)
            let diffLine = DiffLine(
                id: lineId,
                type: type,
                segments: [Segment(
                    id: 0,
                    text: content,
                    isHighlighted: false
                )]
            )

            currentLines.append(diffLine)
            lineId += 1
        }

        // Add final hunk
        if let hunk = currentHunk {
            hunks.append(DiffHunk(
                id: hunkId,
                header: hunk.header,
                lines: currentLines,
                hasNoNewlineAtEnd: hunk.hasNoNewlineAtEnd
            ))
        }

        return enhanceWithWordDiff(hunks)
    }
}

// MARK: - Private functions
private extension GitDiffParser {
    func enhanceWithWordDiff(_ hunks: [DiffHunk]) -> [DiffHunk] {
        var enhanced: [DiffHunk] = []

        for hunk in hunks {
            var enhancedLines: [DiffLine] = []

            // Group lines into pairs (removed + added)
            var i = 0
            while i < hunk.lines.count {
                let line = hunk.lines[i]

                // Check if this is a removed line followed by an added line
                if line.type == .removed &&
                   i + 1 < hunk.lines.count &&
                   hunk.lines[i + 1].type == .added {

                    let removedLine = line
                    let addedLine = hunk.lines[i + 1]

                    // Apply word diff
                    let oldText = removedLine.segments.map { $0.text }.joined()
                    let newText = addedLine.segments.map { $0.text }.joined()

                    let oldSegments = wordDiff(
                        old: Substring(oldText),
                        new: Substring(newText),
                        forOld: true
                    )

                    let newSegments = wordDiff(
                        old: Substring(oldText),
                        new: Substring(newText),
                        forOld: false
                    )

                    enhancedLines.append(DiffLine(
                        id: removedLine.id,
                        type: .removed,
                        segments: oldSegments
                    ))

                    enhancedLines.append(DiffLine(
                        id: addedLine.id,
                        type: .added,
                        segments: newSegments
                    ))
                    i += 2
                } else {
                    // Keep unchanged or solo added/removed lines as-is
                    enhancedLines.append(line)
                    i += 1
                }
            }

            enhanced.append(DiffHunk(
                id: hunk.id,
                header: hunk.header,
                lines: enhancedLines,
                hasNoNewlineAtEnd: hunk.hasNoNewlineAtEnd
            ))
        }

        return enhanced
    }

    func wordDiff(old: Substring, new: Substring, forOld: Bool) -> [Segment] {
        // Extract and preserve leading whitespace
        let oldLeading = old.prefix(while: { $0.isWhitespace })
        let newLeading = new.prefix(while: { $0.isWhitespace })

        // Get content after leading whitespace
        let oldContent = old.drop(while: { $0.isWhitespace })
        let newContent = new.drop(while: { $0.isWhitespace })

        // Split content into words (now safe to split on whitespace)
        let oldWords = oldContent.split(whereSeparator: { $0.isWhitespace })
        let newWords = newContent.split(whereSeparator: { $0.isWhitespace })

        // Use Myers' algorithm for word diff
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

        // Add leading whitespace as first segment (not highlighted)
        let leadingSpace = forOld ? String(oldLeading) : String(newLeading)
        if !leadingSpace.isEmpty {
            segments.append(Segment(
                id: segmentId,
                text: leadingSpace,
                isHighlighted: false
            ))
            segmentId += 1
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

        // Add spaces between words (skip first if it's the leading whitespace)
        let startIndex = leadingSpace.isEmpty ? 0 : 1
        return segments.enumerated().map { index, segment in
            if index >= startIndex && index < segments.count - 1 {
                return Segment(
                    id: segment.id,
                    text: segment.text + " ",
                    isHighlighted: segment.isHighlighted
                )
            }
            return segment
        }
    }
}
