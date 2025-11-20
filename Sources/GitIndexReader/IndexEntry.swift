import Foundation

public struct IndexEntry: Sendable {
    public let path: String
    public let sha1: String
    public let size: UInt32
    public let mtime: Date
    public let fileMode: FileMode
    
    public init(
        path: String,
        sha1: String,
        size: UInt32,
        mtime: Date,
        fileMode: FileMode
    ) {
        self.path = path
        self.sha1 = sha1
        self.size = size
        self.mtime = mtime
        self.fileMode = fileMode
    }
}
