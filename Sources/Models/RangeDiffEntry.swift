import Foundation

/// One row of `git range-diff`: how a commit in the old range corresponds to
/// one in the new range, typically before and after a rebase.
public struct RangeDiffEntry: Sendable, Equatable {
    public enum Change: Sendable, Equatable {
        /// Same patch on both sides (`=`).
        case unchanged
        /// Matched, but the patch differs (`!`).
        case modified
        /// Only in the old range (`<`), e.g. dropped because upstream already had it.
        case removed
        /// Only in the new range (`>`).
        case added
    }

    public let change: Change
    /// Abbreviated hash in the old range, nil for `.added`.
    public let oldCommit: String?
    /// Abbreviated hash in the new range, nil for `.removed`.
    public let newCommit: String?
    public let subject: String
    /// The diff of the two patches for `.modified`, when requested; else empty.
    public let patch: String

    public init(change: Change, oldCommit: String?, newCommit: String?, subject: String, patch: String = "") {
        self.change = change
        self.oldCommit = oldCommit
        self.newCommit = newCommit
        self.subject = subject
        self.patch = patch
    }
}

extension RangeDiffEntry {
    /// `1:  1d2e3f4 ! 1:  5a6b7c8 Subject`; `-` and dashes stand in for the
    /// missing side of an added or removed commit.
    private static let headerRegex = try? NSRegularExpression(
        pattern: #"^\s*(?:-|\d+):\s+([0-9a-f]+|-+)\s+([=!<>])\s+(?:-|\d+):\s+([0-9a-f]+|-+)\s(.*)$"#
    )

    static func parse(_ output: String) -> [RangeDiffEntry] {
        guard let regex = headerRegex else { return [] }
        var entries: [RangeDiffEntry] = []
        var patchLines: [String] = []

        func finishPatch() {
            guard let last = entries.popLast() else { return }
            let patch = patchLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            entries.append(RangeDiffEntry(
                change: last.change,
                oldCommit: last.oldCommit,
                newCommit: last.newCommit,
                subject: last.subject,
                patch: patch
            ))
            patchLines = []
        }

        for line in output.components(separatedBy: "\n") {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let oldRange = Range(match.range(at: 1), in: line),
                  let symbolRange = Range(match.range(at: 2), in: line),
                  let newRange = Range(match.range(at: 3), in: line),
                  let subjectRange = Range(match.range(at: 4), in: line) else {
                if !entries.isEmpty { patchLines.append(line) }
                continue
            }
            finishPatch()
            let change: Change = switch line[symbolRange] {
            case "=": .unchanged
            case "!": .modified
            case "<": .removed
            default: .added
            }
            let old = String(line[oldRange])
            let new = String(line[newRange])
            entries.append(RangeDiffEntry(
                change: change,
                oldCommit: old.allSatisfy { $0 == "-" } ? nil : old,
                newCommit: new.allSatisfy { $0 == "-" } ? nil : new,
                subject: String(line[subjectRange])
            ))
        }
        finishPatch()
        return entries
    }
}
