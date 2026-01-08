import Foundation

public struct WorkingTreeFile: Sendable {
    public let path: String
    public let staged: GitChangeType?     // HEAD → Index
    public let unstaged: GitChangeType?   // Index → Working

    public init(path: String, staged: GitChangeType?, unstaged: GitChangeType?) {
        self.path = path
        self.staged = staged
        self.unstaged = unstaged
    }

    public var hasChanges: Bool {
        staged != nil || unstaged != nil
    }

    public var isStaged: Bool {
        staged != nil
    }

    public var isUnstaged: Bool {
        unstaged != nil
    }
}