import Foundation

public struct FileIdentity: Hashable, Sendable {
    public let dev: UInt64
    public let ino: UInt64
    public let size: UInt64
    public let mtimeNs: UInt64

    public init(dev: UInt64, ino: UInt64, size: UInt64, mtimeNs: UInt64) {
        self.dev = dev
        self.ino = ino
        self.size = size
        self.mtimeNs = mtimeNs
    }
}
