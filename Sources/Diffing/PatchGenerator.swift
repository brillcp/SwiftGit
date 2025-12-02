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
        
        // Header
        patch += "diff --git a/\(file.path) b/\(file.path)\n"
        patch += "--- a/\(file.path)\n"
        patch += "+++ b/\(file.path)\n"
        
        // Hunk
        patch += hunk.header + String.newLine
        
        for line in hunk.lines {
            let lineText = line.segments.map { $0.text }.joined()
            
            switch line.type {
            case .added:
                patch += "+\(lineText)\n"
            case .removed:
                patch += "-\(lineText)\n"
            case .unchanged:
                patch += " \(lineText)\n"
            }
        }
        
        return patch
    }
    
    /// Generate a patch for multiple hunks in a file
    public func generatePatch(hunks: [DiffHunk], file: WorkingTreeFile) -> String {
        var patch = ""
        
        // Header
        patch += "diff --git a/\(file.path) b/\(file.path)\n"
        patch += "--- a/\(file.path)\n"
        patch += "+++ b/\(file.path)\n"
        
        // All hunks
        for hunk in hunks {
            patch += hunk.header + String.newLine
            
            for line in hunk.lines {
                let lineText = line.segments.map { $0.text }.joined()
                
                switch line.type {
                case .added:
                    patch += "+\(lineText)\n"
                case .removed:
                    patch += "-\(lineText)\n"
                case .unchanged:
                    patch += " \(lineText)\n"
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
    
    /// Generate a reverse patch (for unstaging/discarding)
    public func generateReversePatch(hunk: DiffHunk, file: WorkingTreeFile) -> String {
        var patch = ""
        
        // Header
        patch += "diff --git a/\(file.path) b/\(file.path)\n"
        patch += "--- a/\(file.path)\n"
        patch += "+++ b/\(file.path)\n"
        
        // Reversed hunk header
        patch += reverseHunkHeader(hunk.header) + String.newLine
        
        // Reversed lines (swap +/-)
        for line in hunk.lines {
            let lineText = line.segments.map { $0.text }.joined()
            
            switch line.type {
            case .added:
                patch += "-\(lineText)\n"  // Swap
            case .removed:
                patch += "+\(lineText)\n"  // Swap
            case .unchanged:
                patch += " \(lineText)\n"
            }
        }
        
        return patch
    }
}

// MARK: - Private Helpers
private extension PatchGenerator {
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
