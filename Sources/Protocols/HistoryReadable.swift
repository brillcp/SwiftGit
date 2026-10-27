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

    /// How the commits in `base..oldTip` map onto those in `base..newTip`,
    /// e.g. a branch before and after a rebase onto `base`.
    ///
    /// `creationFactor` is git's `--creation-factor`, the percentage of a
    /// patch's size two versions may differ by and still pair up (git
    /// defaults to 60). After a rebase every commit has a counterpart unless
    /// it was dropped, so 100 keeps a heavily reworked commit paired instead
    /// of showing it as one removed and one added.
    func rangeDiff(base: String, oldTip: String, newTip: String, creationFactor: Int?, includePatches: Bool) async throws -> [RangeDiffEntry]
}
