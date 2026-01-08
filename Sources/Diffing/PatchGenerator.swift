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
            patch += "\n\\ No newline at end of file\n"
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
                patch += "\n\\ No newline at end of file\n"
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

    /// Generate a reverse patch (for unstaging/discarding)
    public func generateReversePatch(hunk: DiffHunk, file: WorkingTreeFile) -> String {
        var patch = ""
        patch += makeHeader(for: file)
        patch += reverseHunkHeader(hunk.header) + String.newLine

        for (index, line) in hunk.lines.enumerated() {
            let lineText = line.segments.map { $0.text }.joined()
            let isLastLine = (index == hunk.lines.count - 1)

            switch line.type {
            case .added:  // Swap: becomes removed
                patch += "-\(lineText)"
                if !isLastLine || !hunk.hasNoNewlineAtEnd {
                    patch += String.newLine
                }
            case .removed:  // Swap: becomes added
                patch += "+\(lineText)"
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
            patch += "\n\\ No newline at end of file\n"
        }

        return patch
    }
}

// MARK: - Private Helpers
private extension PatchGenerator {
    func makeHeader(for file: WorkingTreeFile) -> String {
        var header = ""
        header += "diff --git a/\(file.path) b/\(file.path)\n"
        header += "--- a/\(file.path)\n"
        header += "+++ b/\(file.path)\n"
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