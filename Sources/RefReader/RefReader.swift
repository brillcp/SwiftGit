import Foundation
import Collections

public protocol RefReaderProtocol: Actor {
    /// Get all refs (branches, tags, etc.)
    func getRefs() async throws -> OrderedDictionary<String, [GitRef]>

    /// Get HEAD commit SHA
    func getHEAD() async throws -> String?

    /// Get HEAD branch name (nil if detached)
    func getHEADBranch() async throws -> String?

    func getStashes() async throws -> [Stash]
}

// MARK: -
public actor RefReader {
    private let commandRunner: GitCommandable
    private let cache: ObjectCacheProtocol

    public init(
        commandRunner: GitCommandable,
        cache: ObjectCacheProtocol
    ) {
        self.commandRunner = commandRunner
        self.cache = cache
    }
}

// MARK: - RefReaderProtocol
extension RefReader: RefReaderProtocol {
    public func getRefs() async throws -> OrderedDictionary<String, [GitRef]> {
        if let cached: OrderedDictionary<String, [GitRef]> = await cache.get(.refs) {
            return cached
        }

        let result = try await commandRunner.run(.showRef)

        guard result.exitCode == 0 else {
            return [:]
        }

        var refsByHash: OrderedDictionary<String, [GitRef]> = [:]

        let lines = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        var tagRefs: [String: String] = [:]
        var peeledTagRefs: [String: String] = [:]

        for line in lines {
            let parts = line.split(separator: String.space, maxSplits: 1)
            guard parts.count == 2 else { continue }

            let hash = String(parts[0])
            let fullName = String(parts[1])

            // Parse ref type and name
            let ref: GitRef
            let refHeads = "refs/heads/"
            let refRemotes = "refs/remotes/"
            let refTags = "refs/tags/"

            if fullName.hasPrefix(refHeads) {
                let name = String(fullName.dropFirst(refHeads.count))
                ref = GitRef(name: name, hash: hash, type: .localBranch)
            } else if fullName.hasPrefix(refRemotes) {
                let name = String(fullName.dropFirst(refRemotes.count))
                // Skip origin/HEAD (symbolic ref to default branch)
                if name.hasSuffix("/HEAD") {
                    continue
                }
                ref = GitRef(name: name, hash: hash, type: .remoteBranch)
            } else if fullName.hasPrefix(refTags) {
                let name = String(fullName.dropFirst(refTags.count))
                if name.hasSuffix("^{}") {
                    peeledTagRefs[String(name.dropLast(3))] = hash
                } else {
                    tagRefs[name] = hash
                }
                continue
            } else {
                continue // Skip other refs
            }

            refsByHash[hash, default: []].append(ref)
        }

        for name in tagRefs.keys.sorted() {
            let hash = peeledTagRefs[name] ?? tagRefs[name]
            guard let hash else { continue }
            refsByHash[hash, default: []].append(GitRef(name: name, hash: hash, type: .tag))
        }

        await cache.set(.refs, value: refsByHash)
        return refsByHash
    }

    public func getHEAD() async throws -> String? {
        if let cached: String = await cache.get(.head) {
            return cached
        }

        let result = try await commandRunner.run(.revParse(rev: "HEAD"))

        guard result.exitCode == 0 else {
            return nil // Empty repo or invalid HEAD
        }

        let hash = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !hash.isEmpty, hash.isValidSHA else {
            return nil
        }

        await cache.set(.head, value: hash)
        return hash
    }

    public func getHEADBranch() async throws -> String? {
        let result = try await commandRunner.run(.symbolicRef)

        guard result.exitCode == 0 else {
            return nil // Detached HEAD
        }

        let ref = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        if ref.hasPrefix("refs/heads/") {
            return String(ref.dropFirst("refs/heads/".count))
        }

        return nil
    }

    public func getStashes() async throws -> [Stash] {
        if let cached: [Stash] = await cache.get(.stashes) {
            return cached
        }

        let result = try await commandRunner.run(.stashList)

        guard result.exitCode == 0 else {
            return [] // No stashes
        }

        let stashes = Self.parseStashes(result.stdout)
        await cache.set(.stashes, value: stashes)
        return stashes
    }
}

extension RefReader {
    /// Parses `GitCommand.stashList` output: `<selector>\0<hash>\0<time>\0<subject>`
    /// per line, e.g. `stash@{0}`, then a reflog subject such as
    /// `WIP on main: abc1234 message`. The stash message is the subject
    /// after its first colon.
    static func parseStashes(_ output: String) -> [Stash] {
        output.split(separator: String.newLine, omittingEmptySubsequences: true).compactMap { line in
            let fields = line.split(separator: "\0", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4 else { return nil }

            let selector = fields[0]
            guard let open = selector.firstIndex(of: "{"),
                  let close = selector.firstIndex(of: "}"),
                  let index = Int(selector[selector.index(after: open)..<close])
            else { return nil }

            let hash = String(fields[1])
            guard hash.isValidSHA else { return nil }

            let date = TimeInterval(fields[2]).map { Date(timeIntervalSince1970: $0) } ?? Date()

            let subject = fields[3].split(separator: ":", maxSplits: 1)
            let message = subject.count == 2 ? subject[1].trimmingCharacters(in: .whitespaces) : ""

            return Stash(hash: hash, index: index, message: message, date: date)
        }
    }
}
