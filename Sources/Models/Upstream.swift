import Foundation

/// Identifies the remote-tracking counterpart of a local branch.
///
/// Resolved via `git rev-parse --abbrev-ref <branch>@{upstream}`. The result
/// is split on the first `/` so callers can address the remote and the
/// branch on it independently — needed for push/delete/fetch calls that
/// don't accept the combined "origin/foo" form.
public struct Upstream: Sendable, Equatable, Hashable {
    /// Remote name as configured in `branch.<name>.remote` (e.g. `"origin"`,
    /// `"upstream"`).
    public let remote: String

    /// Branch name on the remote, without the `<remote>/` prefix.
    public let branch: String

    public init(remote: String, branch: String) {
        self.remote = remote
        self.branch = branch
    }

    /// `<remote>/<branch>` — the form `git rev-parse --abbrev-ref @{u}` prints
    /// and the form used as a ref in `rev-list` ranges.
    public var refName: String { "\(remote)/\(branch)" }
}
