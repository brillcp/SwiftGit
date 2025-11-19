import Foundation

public struct WorkingTreeStatus: Sendable {
    public let files: [String: WorkingTreeFile]
    
    public init(files: [String: WorkingTreeFile]) {
        self.files = files
    }
}
