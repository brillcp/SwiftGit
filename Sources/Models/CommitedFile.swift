import Foundation

public struct CommitedFile: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let blob: Blob
    public var changeType: GitChangeType

    public init(path: String, blob: Blob, changeType: GitChangeType) {
        self.path = path
        self.blob = blob
        self.changeType = changeType
    }
}