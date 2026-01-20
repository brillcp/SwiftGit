import Foundation

public struct CommitedFile: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public var changeType: GitChangeType

    public init(path: String, changeType: GitChangeType) {
        self.path = path
        self.changeType = changeType
    }
}