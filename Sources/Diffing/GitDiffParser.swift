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
        // Track which line type immediately preceded the last "\ No newline" marker
        var lastLineType: DiffLine.LineType? = nil
        var noNewlineSide: DiffHunk.NoNewlineSide? = nil

        let lines = diffOutput.split(separator: String.newLine, omittingEmptySubsequences: false)

        for line in lines {
            let lineStr = String(line)

            // Skip header lines
            if lineStr.hasPrefix(DiffPrefix.diffGit.rawValue) ||
                lineStr.hasPrefix(DiffPrefix.index.rawValue) ||
                lineStr.hasPrefix(DiffPrefix.remove.rawValue) ||
                lineStr.hasPrefix(DiffPrefix.add.rawValue) ||
                lineStr.hasPrefix(DiffPrefix.binaryFiles.rawValue) {
                continue
            }

            // Hunk header
            if lineStr.hasPrefix(DiffPrefix.at.rawValue) {
                // Save previous hunk if exists
                if let hunk = currentHunk {
                    hunks.append(DiffHunk(
                        id: hunkId,
                        header: hunk.header,
                        lines: currentLines,
                        hasNoNewlineAtEnd: hunk.hasNoNewlineAtEnd,
                        noNewlineSide: noNewlineSide
                    ))
                    hunkId += 1
                }

                let cleanHeader = stripContextHint(lineStr)

                // Start new hunk
                currentHunk = DiffHunk(
                    id: hunkId,
                    header: cleanHeader,
                    lines: [],
                    hasNoNewlineAtEnd: false
                )
                currentLines = []
                lineId = 0
                lastLineType = nil
                noNewlineSide = nil
                continue
            }

            // No newline marker — record which side it applies to based on last line type
            if lineStr.hasPrefix(String.noNewLine) {
                if currentHunk != nil {
                    let side: DiffHunk.NoNewlineSide
                    switch lastLineType {
                    case .removed: side = .old
                    case .added:   side = .new
                    default:       side = .both
                    }
                    // If marker appears twice (both sides), upgrade to .both
                    if noNewlineSide != nil {
                        noNewlineSide = .both
                    } else {
                        noNewlineSide = side
                    }
                    currentHunk = DiffHunk(
                        id: currentHunk!.id,
                        header: currentHunk!.header,
                        lines: currentHunk!.lines,
                        hasNoNewlineAtEnd: true,
                        noNewlineSide: noNewlineSide
                    )
                }
                continue
            }

            // Parse diff line
            guard !lineStr.isEmpty, currentHunk != nil else { continue }

            let type: DiffLine.LineType
            let content: String

            if lineStr.hasPrefix(DiffPrefix.plus.rawValue) {
                type = .added
                content = String(lineStr.dropFirst())
            } else if lineStr.hasPrefix(DiffPrefix.minus.rawValue) {
                type = .removed
                content = String(lineStr.dropFirst())
            } else if lineStr.hasPrefix(DiffPrefix.space.rawValue) {
                type = .unchanged
                content = String(lineStr.dropFirst())
            } else {
                continue
            }

            lastLineType = type

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
                hasNoNewlineAtEnd: hunk.hasNoNewlineAtEnd,
                noNewlineSide: noNewlineSide
            ))
        }

        return enhanceWithWordDiff(hunks)
    }
}

// MARK: - Private functions
private extension GitDiffParser {
    enum DiffPrefix: String {
        case diffGit = "diff --git"
        case index = "index "
        case remove = "--- "
        case add = "+++ "
        case binaryFiles = "Binary files"
        case at = "@@ "
        case plus = "+"
        case minus = "-"
        case space = " "
    }

    func stripContextHint(_ header: String) -> String {
        // Find the second @@ and cut everything after it
        guard let range = header.range(of: #"@@.*?@@"#, options: .regularExpression) else {
            return header
        }

        return String(header[range]) + String.space
    }

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

                    guard oldText != newText || hunk.hasNoNewlineAtEnd else {
                        enhancedLines.append(DiffLine(
                            id: removedLine.id,
                            type: .unchanged,
                            segments: removedLine.segments
                        ))
                        i += 2
                        continue
                    }

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
                hasNoNewlineAtEnd: hunk.hasNoNewlineAtEnd,
                noNewlineSide: hunk.noNewlineSide
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

        // Split on token boundaries for finer-grained highlights.
        // Tokens preserve their trailing separator so reconstruction is lossless.
        let oldTokens = tokenize(oldContent)
        let newTokens = tokenize(newContent)

        // Use Myers' algorithm for token diff
        let difference = newTokens.difference(from: oldTokens)

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
        let tokens = forOld ? oldTokens : newTokens
        let changedIndices = forOld ? removals : insertions

        for (index, token) in tokens.enumerated() {
            segments.append(Segment(
                id: segmentId,
                text: token,
                isHighlighted: changedIndices.contains(index)
            ))
            segmentId += 1
        }

        return segments
    }

    /// Split a string into tokens at identifier boundaries.
    /// Each token includes any immediately following non-identifier, non-whitespace
    /// punctuation so that `foo(` and `foo` are distinct tokens, matching the
    /// granularity of tools like GitKraken.
    func tokenize(_ s: Substring) -> [String] {
        var tokens: [String] = []
        var current = ""

        for ch in s {
            let isIdent = ch.isLetter || ch.isNumber || ch == "_"
            if current.isEmpty {
                current.append(ch)
            } else {
                let lastIsIdent = current.last.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false
                if isIdent == lastIsIdent || ch.isWhitespace {
                    current.append(ch)
                } else {
                    tokens.append(current)
                    current = String(ch)
                }
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
