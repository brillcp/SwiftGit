import Foundation

public protocol RefReaderProtocol: Actor {
    /// Get all refs (branches, tags, etc.)
    func getRefs() async throws -> [String: [GitRef]]

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
    public func getRefs() async throws -> [String: [GitRef]] {
        if let cached: [String: [GitRef]] = await cache.get(.refs) {
            return cached
        }

        let result = try await commandRunner.run(.showRef)

        guard result.exitCode == 0 else {
            return [:]
        }

        var refsByHash: [String: [GitRef]] = [:]

        let lines = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        for line in lines {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let hash = String(parts[0])
            let fullName = String(parts[1])

            // Parse ref type and name
            let ref: GitRef
            if fullName.hasPrefix("refs/heads/") {
                let name = String(fullName.dropFirst("refs/heads/".count))
                ref = GitRef(name: name, hash: hash, type: .localBranch)
            } else if fullName.hasPrefix("refs/remotes/") {
                let name = String(fullName.dropFirst("refs/remotes/".count))
                ref = GitRef(name: name, hash: hash, type: .remoteBranch)
            } else if fullName.hasPrefix("refs/tags/") {
                let name = String(fullName.dropFirst("refs/tags/".count))
                ref = GitRef(name: name, hash: hash, type: .tag)
            } else {
                continue // Skip other refs
            }

            refsByHash[hash, default: []].append(ref)
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

        let lines = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }

        var stashes: [Stash] = []

        for line in lines {
            // Format: "stash@{0}: WIP on main: abc1234 commit message"
            let parts = line.split(separator: ":", maxSplits: 2)
            guard parts.count >= 2 else { continue }

            // Extract index from "stash@{0}"
            let stashRef = String(parts[0])
            guard let indexStart = stashRef.firstIndex(of: "{"),
                  let indexEnd = stashRef.firstIndex(of: "}"),
                  let index = Int(stashRef[stashRef.index(after: indexStart)..<indexEnd])
            else { continue }

            // Get hash and date for this stash
            let hashResult = try await commandRunner.run(.revParse(rev: stashRef))
            guard hashResult.exitCode == 0 else { continue }
            let hash = hashResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

            // Get commit date
            let dateResult = try await commandRunner.run(.showCommitDate(ref: stashRef))
            let date: Date
            if dateResult.exitCode == 0,
               let timestamp = TimeInterval(dateResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) {
                date = Date(timeIntervalSince1970: timestamp)
            } else {
                date = Date()
            }

            // Message is everything after second colon
            let message = parts.count == 3 ? String(parts[2]).trimmingCharacters(in: .whitespaces) : ""
            stashes.append(Stash(hash: hash, index: index, message: message, date: date))
        }

        await cache.set(.stashes, value: stashes)
        return stashes
    }
}
