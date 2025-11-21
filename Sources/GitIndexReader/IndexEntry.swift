import Foundation

public struct IndexEntry: Sendable {
    public let path: String
    public let sha1: String
    public let size: UInt32
    public let mtime: Date
    public let mtimeNSec: UInt32
    public let ctime: Date
    public let ctimeNSec: UInt32
    public let dev: UInt32
    public let ino: UInt32
    public let uid: UInt32
    public let gid: UInt32
    public let fileMode: FileMode

    public init(
        path: String,
        sha1: String,
        size: UInt32,
        mtime: Date,
        mtimeNSec: UInt32,
        ctime: Date,
        ctimeNSec: UInt32,
        dev: UInt32,
        ino: UInt32,
        uid: UInt32,
        gid: UInt32,
        fileMode: FileMode
    ) {
        self.path = path
        self.sha1 = sha1
        self.size = size
        self.mtime = mtime
        self.mtimeNSec = mtimeNSec
        self.ctime = ctime
        self.ctimeNSec = ctimeNSec
        self.dev = dev
        self.ino = ino
        self.uid = uid
        self.gid = gid
        self.fileMode = fileMode
    }
}
