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

        let lineNums = hunkLineNumbers(hunk)

        if let (removedIndex, addedIndex) = pairedSubstitution(for: lineIndex, in: hunk) {
            let removedText = hunk.lines[removedIndex].segments.map { $0.text }.joined()
            let addedText   = hunk.lines[addedIndex].segments.map { $0.text }.joined()
            let old = lineNums[removedIndex].old ?? oldLineNum ?? 1
            let new = lineNums[addedIndex].new ?? newLineNum ?? old
            var patch = makeHeader(for: file)
            patch += "@@ -\(old),1 +\(new),1 @@\(String.newLine)"
            patch += "-\(removedText)\(String.newLine)"
            patch += "+\(addedText)\(String.newLine)"
            return patch
        }

        let lineText = line.segments.map { $0.text }.joined()
        var patch = makeHeader(for: file)

        switch line.type {
        case .added:
            let oldAnchor = previousOldAnchor(before: lineIndex, lineNums: lineNums, hunk: hunk)
            patch += "@@ -\(oldAnchor),0 +\(oldAnchor + 1),1 @@\(String.newLine)"
            patch += "+\(lineText)\(String.newLine)"
        case .removed:
            let oldPos = lineNums[lineIndex].old ?? oldLineNum ?? 1
            patch += "@@ -\(oldPos),1 +\(max(0, oldPos - 1)),0 @@\(String.newLine)"
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

        let lineNums = hunkLineNumbers(hunk)

        if let (removedIndex, addedIndex) = pairedSubstitution(for: lineIndex, in: hunk) {
            let removedText = hunk.lines[removedIndex].segments.map { $0.text }.joined()
            let addedText   = hunk.lines[addedIndex].segments.map { $0.text }.joined()
            let new = lineNums[addedIndex].new ?? newLineNum ?? 1
            let old = lineNums[removedIndex].old ?? oldLineNum ?? new
            var patch = makeHeader(for: file)
            patch += "@@ -\(new),1 +\(old),1 @@\(String.newLine)"
            patch += "-\(addedText)\(String.newLine)"
            patch += "+\(removedText)\(String.newLine)"
            return patch
        }

        let lineText = line.segments.map { $0.text }.joined()
        var patch = makeHeader(for: file)

        switch line.type {
        case .added:
            let newPos = lineNums[lineIndex].new ?? newLineNum ?? 1
            patch += "@@ -\(newPos),1 +\(max(0, newPos - 1)),0 @@\(String.newLine)"
            patch += "-\(lineText)\(String.newLine)"
        case .removed:
            let newAnchor = previousNewAnchor(before: lineIndex, lineNums: lineNums, hunk: hunk)
            patch += "@@ -\(newAnchor),0 +\(newAnchor + 1),1 @@\(String.newLine)"
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
    func previousOldAnchor(before lineIndex: Int, lineNums: [(old: Int?, new: Int?)], hunk: DiffHunk) -> Int {
        for i in stride(from: lineIndex - 1, through: 0, by: -1) {
            if let old = lineNums[i].old { return old }
        }
        return max(0, hunkOldStart(hunk) - 1)
    }

    func previousNewAnchor(before lineIndex: Int, lineNums: [(old: Int?, new: Int?)], hunk: DiffHunk) -> Int {
        for i in stride(from: lineIndex - 1, through: 0, by: -1) {
            if let new = lineNums[i].new { return new }
        }
        return max(0, hunkNewStart(hunk) - 1)
    }

    func hunkOldStart(_ hunk: DiffHunk) -> Int {
        let pattern = #"@@ -(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: hunk.header, range: NSRange(hunk.header.startIndex..., in: hunk.header)),
              let value = Int((hunk.header as NSString).substring(with: match.range(at: 1)))
        else { return 1 }
        return value
    }

    func hunkNewStart(_ hunk: DiffHunk) -> Int {
        let pattern = #"\+(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: hunk.header, range: NSRange(hunk.header.startIndex..., in: hunk.header)),
              let value = Int((hunk.header as NSString).substring(with: match.range(at: 1)))
        else { return 1 }
        return value
    }

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

    /// Find the paired (removedIndex, addedIndex) for a line that is part of a
    /// clean N-line substitution: a contiguous run of N removed lines
    /// immediately followed by a contiguous run of N added lines (e.g.
    /// `---+++` with matching N).
    ///
    /// Lines pair positionally — the Nth remove pairs with the Nth add. So
    /// clicking either side of `s/foo/bar/` stages both halves together,
    /// matching GitKraken's "modify line" UX.
    ///
    /// **Returns nil when the block sizes differ.** Asymmetric runs like
    /// `[7 removes, 3 adds]` are not a substitution — they're a deletion
    /// plus an unrelated insertion, and pairing would silently stage one
    /// side of an unrelated edit. Each line in such a block is handled
    /// independently as a single-line patch.
    func pairedSubstitution(for lineIndex: Int, in hunk: DiffHunk) -> (removedIndex: Int, addedIndex: Int)? {
        let lines = hunk.lines
        guard lineIndex < lines.count else { return nil }
        let lineType = lines[lineIndex].type
        guard lineType == .removed || lineType == .added else { return nil }

        // Locate the boundaries of the removes run and the adds run that the
        // clicked line sits in (or is adjacent to). The removes block must
        // come immediately before the adds block — gaps disqualify pairing.
        let removesStart: Int
        let removesEnd: Int   // inclusive
        let addsStart: Int
        let addsEnd: Int      // inclusive

        if lineType == .removed {
            var rs = lineIndex
            while rs > 0 && lines[rs - 1].type == .removed { rs -= 1 }
            var re = lineIndex
            while re + 1 < lines.count && lines[re + 1].type == .removed { re += 1 }
            // Adds must immediately follow the removes block.
            guard re + 1 < lines.count, lines[re + 1].type == .added else { return nil }
            var ae = re + 1
            while ae + 1 < lines.count && lines[ae + 1].type == .added { ae += 1 }
            removesStart = rs
            removesEnd = re
            addsStart = re + 1
            addsEnd = ae
        } else {
            // .added — find the surrounding adds run and check that a removes
            // run sits immediately before it.
            var as_ = lineIndex
            while as_ > 0 && lines[as_ - 1].type == .added { as_ -= 1 }
            var ae = lineIndex
            while ae + 1 < lines.count && lines[ae + 1].type == .added { ae += 1 }
            guard as_ > 0, lines[as_ - 1].type == .removed else { return nil }
            var rs = as_ - 1
            while rs > 0 && lines[rs - 1].type == .removed { rs -= 1 }
            removesStart = rs
            removesEnd = as_ - 1
            addsStart = as_
            addsEnd = ae
        }

        let removesCount = removesEnd - removesStart + 1
        let addsCount = addsEnd - addsStart + 1

        // Strict equality. If a user changed N lines into N lines, every
        // remove has a clean partner. Anything else (e.g. 7 → 3) is not a
        // substitution and falls through to single-line patching.
        guard removesCount == addsCount else { return nil }

        if lineType == .removed {
            let offset = lineIndex - removesStart
            return (removedIndex: lineIndex, addedIndex: addsStart + offset)
        } else {
            let offset = lineIndex - addsStart
            return (removedIndex: removesStart + offset, addedIndex: lineIndex)
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
