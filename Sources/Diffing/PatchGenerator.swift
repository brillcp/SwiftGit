import Foundation

/// Generates Git patch files from hunks
public struct PatchGenerator {
    public init() {}
}

// MARK: - Public functions
extension PatchGenerator {
    /// Generate a patch for a single hunk
    public func generatePatch(hunk: DiffHunk, file: WorkingTreeFile) -> String {
        var patch = ""
        patch += makeHeader(for: file)
        patch += hunk.header + String.newLine

        // Find the index of the line after which "\ No newline" should be emitted.
        // For .old side: after the last removed line. For .new/.both/nil: after the last added line.
        let noNewlineAfterIndex: Int? = hunk.hasNoNewlineAtEnd ? noNewlineMarkerIndex(hunk) : nil

        for (index, line) in hunk.lines.enumerated() {
            let lineText = line.segments.map { $0.text }.joined()

            switch line.type {
            case .added:
                patch += "+\(lineText)\(String.newLine)"
            case .removed:
                patch += "-\(lineText)\(String.newLine)"
            case .unchanged:
                patch += " \(lineText)\(String.newLine)"
            }

            if index == noNewlineAfterIndex {
                patch += String.noNewLine + String.newLine
            }
        }

        return patch
    }

    /// Generate a patch for multiple hunks in a file
    public func generatePatch(hunks: [DiffHunk], file: WorkingTreeFile) -> String {
        var patch = ""
        patch += makeHeader(for: file)

        for hunk in hunks {
            patch += hunk.header + String.newLine

            let noNewlineAfterIndex: Int? = hunk.hasNoNewlineAtEnd ? noNewlineMarkerIndex(hunk) : nil

            for (index, line) in hunk.lines.enumerated() {
                let lineText = line.segments.map { $0.text }.joined()

                switch line.type {
                case .added:
                    patch += "+\(lineText)\(String.newLine)"
                case .removed:
                    patch += "-\(lineText)\(String.newLine)"
                case .unchanged:
                    patch += " \(lineText)\(String.newLine)"
                }

                if index == noNewlineAfterIndex {
                    patch += String.noNewLine + String.newLine
                }
            }
        }

        return patch
    }

    /// Generate patches for multiple files
    public func generatePatch(changes: [(file: WorkingTreeFile, hunks: [DiffHunk])]) -> String {
        changes
            .map { generatePatch(hunks: $0.hunks, file: $0.file) }
            .joined(separator: String.newLine)
    }

    /// Generate a patch for staging a single line from a hunk.
    /// Uses zero-context (--unidiff-zero) format so git applies it without needing surrounding lines.
    /// - Parameters:
    ///   - lineIndex: Index of the line within `hunk.lines` to stage
    ///   - hunk: The parent hunk containing the line
    ///   - file: The working tree file
    ///   - oldLineNum: The 1-based old-file line number for the target line
    ///   - newLineNum: The 1-based new-file line number for the target line
    public func generateSingleLinePatch(
        lineIndex: Int,
        in hunk: DiffHunk,
        file: WorkingTreeFile,
        oldLineNum: Int?,
        newLineNum: Int?
    ) -> String {
        let line = hunk.lines[lineIndex]
        guard line.type == .added || line.type == .removed else { return "" }

        let lineText = line.segments.map { $0.text }.joined()
        var patch = makeHeader(for: file)

        switch line.type {
        case .added:
            // Adding: old side has 0 lines at (newLineNum - 1), new side has 1 line at newLineNum
            let pos = (newLineNum ?? 1) - 1
            patch += "@@ -\(pos),0 +\(newLineNum ?? 1),1 @@\(String.newLine)"
            patch += "+\(lineText)\(String.newLine)"
        case .removed:
            let oldStart = oldLineNum ?? 1
            let newPos = max(0, oldStart - 1)
            patch += "@@ -\(oldStart),1 +\(newPos),0 @@\(String.newLine)"
            patch += "-\(lineText)\(String.newLine)"
        case .unchanged:
            break
        }

        return patch
    }

    /// Generate a reverse single-line patch (for unstaging one line).
    public func generateReverseSingleLinePatch(
        lineIndex: Int,
        in hunk: DiffHunk,
        file: WorkingTreeFile,
        oldLineNum: Int?,
        newLineNum: Int?
    ) -> String {
        let line = hunk.lines[lineIndex]
        guard line.type == .added || line.type == .removed else { return "" }

        let lineText = line.segments.map { $0.text }.joined()
        var patch = makeHeader(for: file)

        switch line.type {
        case .added:
            // Reverse of add: remove the line that was added.
            // Symmetric to the forward `.removed` case — `+(N-1),0`.
            let newStart = newLineNum ?? 1
            let pos = max(0, newStart - 1)
            patch += "@@ -\(newStart),1 +\(pos),0 @@\(String.newLine)"
            patch += "-\(lineText)\(String.newLine)"
        case .removed:
            // Reverse of remove: re-add the line that was removed
            let pos = (oldLineNum ?? 1) - 1
            patch += "@@ -\(pos),0 +\(oldLineNum ?? 1),1 @@\(String.newLine)"
            patch += "+\(lineText)\(String.newLine)"
        case .unchanged:
            break
        }

        return patch
    }

    /// Generate a reverse patch (for unstaging/discarding)
    public func generateReversePatch(hunk: DiffHunk, file: WorkingTreeFile) -> String {
        var patch = ""
        patch += makeHeader(for: file)  // Already has \n at end
        patch += reverseHunkHeader(hunk.header) + String.newLine

        // In the reverse patch, added lines become '-' and removed lines become '+'.
        // The "\ No newline" marker must follow the line that represents the side lacking a newline.
        // - original .old side (removed) → in reverse becomes '+'; marker follows last '+' from removed
        // - original .new side (added)   → in reverse becomes '-'; marker follows last '-' from added
        // - .both / nil                  → follows last result line (unchanged or removed→'+')
        let reverseNoNewlineAfterIndex: Int? = hunk.hasNoNewlineAtEnd
            ? reverseNoNewlineMarkerIndex(hunk)
            : nil

        for (index, line) in hunk.lines.enumerated() {
            let lineText = line.segments.map { $0.text }.joined()

            switch line.type {
            case .added:
                patch += "-\(lineText)\(String.newLine)"
            case .removed:
                patch += "+\(lineText)\(String.newLine)"
            case .unchanged:
                patch += " \(lineText)\(String.newLine)"
            }

            if index == reverseNoNewlineAfterIndex {
                patch += String.noNewLine + String.newLine
            }
        }

        return patch
    }
}

// MARK: - Private Helpers
private extension PatchGenerator {
    /// Index of the line after which "\ No newline at end of file" should be emitted in a forward patch.
    /// - .old side → after the last removed line
    /// - .new/.both/nil → after the last added line (fallback: last line overall)
    func noNewlineMarkerIndex(_ hunk: DiffHunk) -> Int {
        switch hunk.noNewlineSide {
        case .old:
            // Marker follows last removed line
            if let idx = hunk.lines.indices.reversed().first(where: { hunk.lines[$0].type == .removed }) {
                return idx
            }
        default:
            // Marker follows last added line
            if let idx = hunk.lines.indices.reversed().first(where: { hunk.lines[$0].type == .added }) {
                return idx
            }
        }
        return hunk.lines.count - 1
    }

    /// Index of the line after which "\ No newline at end of file" should be emitted in a reverse patch.
    /// In the reverse, removed→'+' and added→'-', so sides flip.
    /// - original .old (removed→'+') → marker after last removed line (becomes '+')
    /// - original .new (added→'-')   → marker after last added line (becomes '-')
    /// - .both/nil                   → after last removed-or-unchanged line
    func reverseNoNewlineMarkerIndex(_ hunk: DiffHunk) -> Int {
        switch hunk.noNewlineSide {
        case .old:
            // Original removed lines become '+' in reverse; marker after last removed
            if let idx = hunk.lines.indices.reversed().first(where: { hunk.lines[$0].type == .removed }) {
                return idx
            }
        case .new:
            // Original added lines become '-' in reverse; marker after last added
            if let idx = hunk.lines.indices.reversed().first(where: { hunk.lines[$0].type == .added }) {
                return idx
            }
        default:
            // Marker after last result line (unchanged or removed→'+')
            if let idx = hunk.lines.indices.reversed().first(where: { hunk.lines[$0].type == .unchanged || hunk.lines[$0].type == .removed }) {
                return idx
            }
        }
        return hunk.lines.count - 1
    }

    func makeHeader(for file: WorkingTreeFile) -> String {
        var header = ""
        header += "diff --git a/\(file.path) b/\(file.path)\(String.newLine)"
        header += "--- a/\(file.path)\(String.newLine)"
        header += "+++ b/\(file.path)\(String.newLine)"
        return header
    }

    /// Find the paired (removedIndex, addedIndex) for a line that is part of a contiguous
    /// remove/add substitution block. Returns nil if the line has no paired counterpart.
    ///
    /// A substitution block is a run of consecutive removed lines immediately followed by a run
    /// of consecutive added lines (e.g. `---+++`). Lines are paired positionally: the Nth remove
    /// pairs with the Nth add. If the block sizes differ, unpaired lines return nil.
    func pairedSubstitution(for lineIndex: Int, in hunk: DiffHunk) -> (removedIndex: Int, addedIndex: Int)? {
        let lines = hunk.lines
        guard lineIndex < lines.count else { return nil }
        let lineType = lines[lineIndex].type
        guard lineType == .removed || lineType == .added else { return nil }

        // Find the start of the contiguous removed run that contains (or precedes) this line.
        // For a removed line: scan back to the block start, then forward to find the adds block.
        // For an added line: scan back through the adds to find the removes block before it.

        var blockStart = lineIndex
        if lineType == .removed {
            // Walk back to find start of the removes run
            while blockStart > 0 && lines[blockStart - 1].type == .removed { blockStart -= 1 }
            // Walk forward past all removes to find start of adds run
            var addsStart = lineIndex
            while addsStart + 1 < lines.count && lines[addsStart + 1].type == .removed { addsStart += 1 }
            addsStart += 1  // first potential add
            guard addsStart < lines.count, lines[addsStart].type == .added else { return nil }

            // Offset of this remove within the removes run
            let removeOffset = lineIndex - blockStart

            var addsCount = 0
            var addsEnd = addsStart
            while addsEnd < lines.count && lines[addsEnd].type == .added { addsEnd += 1; addsCount += 1 }

            guard removeOffset < addsCount else { return nil }
            return (removedIndex: lineIndex, addedIndex: addsStart + removeOffset)

        } else {
            // lineType == .added
            // Walk back through adds to find start of adds run
            var addsStart = lineIndex
            while addsStart > 0 && lines[addsStart - 1].type == .added { addsStart -= 1 }
            // Walk back past any non-removed lines — the removes run must immediately precede the adds run
            guard addsStart > 0, lines[addsStart - 1].type == .removed else { return nil }

            // Find start of the removes run
            var removesEnd = addsStart - 1
            var removesStart = removesEnd
            while removesStart > 0 && lines[removesStart - 1].type == .removed { removesStart -= 1 }

            let addOffset = lineIndex - addsStart
            let removesCount = removesEnd - removesStart + 1
            guard addOffset < removesCount else { return nil }
            return (removedIndex: removesStart + addOffset, addedIndex: lineIndex)
        }
    }

    /// Compute (old, new) line numbers for each line in a hunk by walking from the hunk header start.
    func hunkLineNumbers(_ hunk: DiffHunk) -> [(old: Int?, new: Int?)] {
        // Parse oldStart and newStart from the hunk header "@@ -oldStart,... +newStart,... @@"
        let pattern = #"@@ -(\d+)[,\d]* \+(\d+)"#
        var oldLine: Int?
        var newLine: Int?
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: hunk.header, range: NSRange(hunk.header.startIndex..., in: hunk.header)),
           match.numberOfRanges >= 3 {
            oldLine = Int((hunk.header as NSString).substring(with: match.range(at: 1)))
            newLine = Int((hunk.header as NSString).substring(with: match.range(at: 2)))
        }

        var result: [(old: Int?, new: Int?)] = []
        for line in hunk.lines {
            switch line.type {
            case .unchanged:
                result.append((old: oldLine, new: newLine))
                oldLine = oldLine.map { $0 + 1 }
                newLine = newLine.map { $0 + 1 }
            case .removed:
                result.append((old: oldLine, new: nil))
                oldLine = oldLine.map { $0 + 1 }
            case .added:
                result.append((old: nil, new: newLine))
                newLine = newLine.map { $0 + 1 }
            }
        }
        return result
    }

    func reverseHunkHeader(_ header: String) -> String {
        // Input:  "@@ -10,5 +12,7 @@"
        // Output: "@@ -12,7 +10,5 @@"

        let pattern = #"@@ -(\d+),(\d+) \+(\d+),(\d+) @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
              match.numberOfRanges == 5 else {
            return header
        }

        let oldStart = (header as NSString).substring(with: match.range(at: 1))
        let oldCount = (header as NSString).substring(with: match.range(at: 2))
        let newStart = (header as NSString).substring(with: match.range(at: 3))
        let newCount = (header as NSString).substring(with: match.range(at: 4))

        return "@@ -\(newStart),\(newCount) +\(oldStart),\(oldCount) @@"
    }
}
