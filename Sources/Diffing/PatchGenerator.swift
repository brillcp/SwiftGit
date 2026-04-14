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

        for (index, line) in hunk.lines.enumerated() {
            let lineText = line.segments.map { $0.text }.joined()
            let isLastLine = (index == hunk.lines.count - 1)

            switch line.type {
            case .added:
                patch += "+\(lineText)"
                if !isLastLine || !hunk.hasNoNewlineAtEnd {
                    patch += String.newLine
                }
            case .removed:
                patch += "-\(lineText)"
                if !isLastLine || !hunk.hasNoNewlineAtEnd {
                    patch += String.newLine
                }
            case .unchanged:
                patch += " \(lineText)"
                if !isLastLine || !hunk.hasNoNewlineAtEnd {
                    patch += String.newLine
                }
            }
        }

        if hunk.hasNoNewlineAtEnd {
            patch += String.noNewLineAtEnd
        }

        return patch
    }

    /// Generate a patch for multiple hunks in a file
    public func generatePatch(hunks: [DiffHunk], file: WorkingTreeFile) -> String {
        var patch = ""
        patch += makeHeader(for: file)

        for hunk in hunks {
            patch += hunk.header + String.newLine

            for (index, line) in hunk.lines.enumerated() {
                let lineText = line.segments.map { $0.text }.joined()
                let isLastLine = (index == hunk.lines.count - 1)

                switch line.type {
                case .added:
                    patch += "+\(lineText)"
                    if !isLastLine || !hunk.hasNoNewlineAtEnd {
                        patch += String.newLine
                    }
                case .removed:
                    patch += "-\(lineText)"
                    if !isLastLine || !hunk.hasNoNewlineAtEnd {
                        patch += String.newLine
                    }
                case .unchanged:
                    patch += " \(lineText)"
                    if !isLastLine || !hunk.hasNoNewlineAtEnd {
                        patch += String.newLine
                    }
                }
            }

            if hunk.hasNoNewlineAtEnd {
                patch += String.noNewLineAtEnd
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
            // Removing: old side has 1 line at oldLineNum, new side has 0 lines
            patch += "@@ -\(oldLineNum ?? 1),1 +\(oldLineNum ?? 1),0 @@\(String.newLine)"
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
            // Reverse of add: remove the line that was added
            patch += "@@ -\(newLineNum ?? 1),1 +\(newLineNum ?? 1),0 @@\(String.newLine)"
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

        // Find last result line
        var lastResultLineIndex = -1
        for (index, line) in hunk.lines.enumerated() {
            if line.type == .unchanged || line.type == .removed {
                lastResultLineIndex = index
            }
        }

        // Process lines
        for (index, line) in hunk.lines.enumerated() {
            let lineText = line.segments.map { $0.text }.joined()
            let isLastResultLine = (index == lastResultLineIndex)

            switch line.type {
            case .added:
                patch += "-\(lineText)\(String.newLine)"
            case .removed:
                patch += "+\(lineText)\(String.newLine)"
                if isLastResultLine && hunk.hasNoNewlineAtEnd {
                    patch += "\(String.noNewLine)\(String.newLine)"
                }
            case .unchanged:
                patch += " \(lineText)\(String.newLine)"
                if isLastResultLine && hunk.hasNoNewlineAtEnd {
                    patch += "\(String.noNewLine)\(String.newLine)"
                }
            }
        }

        return patch
    }
}

// MARK: - Private Helpers
private extension PatchGenerator {
    func makeHeader(for file: WorkingTreeFile) -> String {
        var header = ""
        header += "diff --git a/\(file.path) b/\(file.path)\(String.newLine)"
        header += "--- a/\(file.path)\(String.newLine)"
        header += "+++ b/\(file.path)\(String.newLine)"
        return header
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
