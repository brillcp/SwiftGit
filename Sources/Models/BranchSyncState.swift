import Foundation

/// A local branch's upstream and how far the two have diverged.
public struct BranchSyncState: Sendable, Equatable {
    public let upstream: Upstream
    public let aheadBehind: AheadBehind

    public init(upstream: Upstream, aheadBehind: AheadBehind) {
        self.upstream = upstream
        self.aheadBehind = aheadBehind
    }
}

extension BranchSyncState {
    /// Parses `GitCommand.branchSyncState` output into states keyed by local
    /// branch name. Leaves out branches with no upstream, a local upstream
    /// (`remote = .`), or an upstream whose remote-tracking ref is gone, the
    /// same branches `rev-parse <branch>@{upstream}` has no answer for.
    static func parse(_ output: String) -> [String: BranchSyncState] {
        var states: [String: BranchSyncState] = [:]

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\0", maxSplits: 3, omittingEmptySubsequences: false)
            guard fields.count == 4 else { continue }

            let localPrefix = "refs/heads/"
            let localRef = fields[0]
            let remote = String(fields[1])
            let trackingRef = fields[2]
            let track = fields[3]

            guard localRef.hasPrefix(localPrefix),
                  !remote.isEmpty, remote != ".",
                  !track.contains("gone")
            else { continue }

            // The tracking ref is refs/remotes/<remote>/<branch>. Strip the
            // known remote name rather than splitting on a slash, since both
            // the remote and the branch may contain one.
            let trackingPrefix = "refs/remotes/\(remote)/"
            guard trackingRef.hasPrefix(trackingPrefix) else { continue }
            let branch = String(trackingRef.dropFirst(trackingPrefix.count))
            guard !branch.isEmpty else { continue }

            let name = String(localRef.dropFirst(localPrefix.count))
            states[name] = BranchSyncState(
                upstream: Upstream(remote: remote, branch: branch),
                aheadBehind: parseTrack(track)
            )
        }

        return states
    }

    /// Parses `%(upstream:track)` text: empty when in sync, otherwise
    /// `[ahead N]`, `[behind M]` or `[ahead N, behind M]`.
    static func parseTrack(_ track: Substring) -> AheadBehind {
        var ahead = 0
        var behind = 0
        let parts = track
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            .split(separator: ",")

        for part in parts {
            let words = part.split(separator: " ")
            guard words.count == 2, let count = Int(words[1]) else { continue }
            switch words[0] {
            case "ahead": ahead = count
            case "behind": behind = count
            default: continue
            }
        }

        return AheadBehind(ahead: ahead, behind: behind)
    }
}
