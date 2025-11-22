import Foundation

public struct CommitedFile: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let blob: Blob
    public var changeType: GitChangeType
}
