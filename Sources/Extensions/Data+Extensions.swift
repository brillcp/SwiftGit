import Foundation
import Compression
import CryptoKit

extension Data {
    func toHexString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }

    func sha1() -> String {
        let hash = Insecure.SHA1.hash(data: self)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    var decompressed: Data {
        let size = 8_000_000
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        let result = dropFirst(2).withUnsafeBytes({
            let read = compression_decode_buffer(
                buffer,
                size,
                $0.baseAddress!.bindMemory(
                    to: UInt8.self,
                    capacity: 1
                ),
                $0.count,
                nil,
                COMPRESSION_ZLIB
            )
            return Data(bytes: buffer, count: read)
        })
        return result
    }

    func readUInt16(at offset: inout Int) -> UInt16 {
        let value = self[offset..<offset+2].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        offset += 2
        return value
    }

    func readHex20(at offset: inout Int) -> String {
        let bytes = self[offset..<offset+20]
        offset += 20
        return bytes.toHexString()
    }

    func readUInt32(at offset: inout Int) -> UInt32 {
        let value = self[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        offset += 4
        return value
    }

    func readUInt64(at offset: inout Int, index: Int) -> UInt64 {
        let position = offset + (index * 8)
        guard position + 8 <= self.count else { return 0 }
        return self[position..<position+8].withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
    }
}
