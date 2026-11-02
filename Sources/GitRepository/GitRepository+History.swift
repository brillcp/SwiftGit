import Foundation

extension GitRepository: HistoryReadable {
    public func mergeBase(_ first: String, _ second: String) async throws -> String? {
        let result = try await commandRunner.run(.mergeBase(first, second))
        // Exit 1 with no output means no common ancestor.
        if result.exitCode == 1, result.stderr.isEmpty { return nil }
        guard result.exitCode == 0 else {
            throw GitError.historyFailed(reason: result.stderr)
        }
        let hash = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.isEmpty ? nil : hash
    }

    public func fileHistory(path: String, range: String, limit: Int) async throws -> [Commit] {
        let result = try await commandRunner.run(.fileHistory(range: range, path: path, limit: limit))
        guard result.exitCode == 0 else {
            throw GitError.historyFailed(reason: result.stderr)
        }
        return result.stdout
            .components(separatedBy: "\u{1e}")
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }
            .compactMap { try? Commit.parse(from: $0) }
    }

    public func rangeDiff(base: String, oldTip: String, newTip: String, creationFactor: Int?, includePatches: Bool) async throws -> [RangeDiffEntry] {
        let result = try await commandRunner.run(
            .rangeDiff(base: base, oldTip: oldTip, newTip: newTip, creationFactor: creationFactor, includePatches: includePatches)
        )
        guard result.exitCode == 0 else {
            throw GitError.historyFailed(reason: result.stderr)
        }
        return RangeDiffEntry.parse(result.stdout)
    }
}
