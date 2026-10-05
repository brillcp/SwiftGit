import Foundation

/// How many commits a local branch is ahead/behind its upstream.
///
/// Returned by `getAheadBehind(local:upstream:)`, backed by
/// `git rev-list --left-right --count <local>...<upstream>`.
public struct AheadBehind: Sendable, Equatable {
    public let ahead: Int
    public let behind: Int

    public init(ahead: Int, behind: Int) {
        self.ahead = ahead
        self.behind = behind
    }
}
