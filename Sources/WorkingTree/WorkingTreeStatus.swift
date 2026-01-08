import Foundation

public struct WorkingTreeStatus: Sendable {
    public var files: [String: WorkingTreeFile]

    public init(files: [String: WorkingTreeFile]) {
        self.files = files
    }
}