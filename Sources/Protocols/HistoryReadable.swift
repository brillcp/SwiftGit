import Foundation

/// Read-only questions about history and content across refs.
public protocol HistoryReadable: Actor {
    /// The best common ancestor of two revisions, or nil when they share none.
    func mergeBase(_ first: String, _ second: String) async throws -> String?

    /// Commits in `range` (e.g. `base..HEAD`) that touched `path`, newest first.
    func fileHistory(path: String, range: String, limit: Int) async throws -> [Commit]

    /// Lines containing `text` (a fixed string) in `ref`, or in the working
    /// tree when nil. Binary files are skipped; at most `limit` matches.
    func search(_ text: String, in ref: String?, limit: Int) async throws -> [GrepMatch]

    /// How the commits in `oldRange` map onto those in `newRange`, e.g. a
    /// branch before and after a rebase.
    func rangeDiff(oldRange: String, newRange: String, includePatches: Bool) async throws -> [RangeDiffEntry]
}
