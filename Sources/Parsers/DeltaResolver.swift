import Foundation

public protocol DeltaResolverProtocol {
    /// Apply delta instructions to base data
    func apply(delta: Data, to base: Data) throws -> Data
}

// MARK: -
public final class DeltaResolver {
    public init() {}
}

// MARK: - DeltaResolverProtocol
extension DeltaResolver: DeltaResolverProtocol {
    public func apply(delta: Data, to base: Data) throws -> Data {
        var idx = 0
        // Read source (base) size and target size (both varints)
        let _ = readGitVarInt(delta, start: &idx) // source size (can be ignored for safety)
        let targetSize = readGitVarInt(delta, start: &idx)

        var output = Data()
        output.reserveCapacity(targetSize)

        while idx < delta.count {
            let opcode = Int(delta[idx])
            idx += 1
            if (opcode & 0x80) != 0 {
                // copy from base
                var cpOffset = 0
                var cpSize = 0
                if (opcode & 0x01) != 0 { cpOffset |= Int(delta[idx]); idx += 1 }
                if (opcode & 0x02) != 0 { cpOffset |= Int(delta[idx]) << 8; idx += 1 }
                if (opcode & 0x04) != 0 { cpOffset |= Int(delta[idx]) << 16; idx += 1 }
                if (opcode & 0x08) != 0 { cpOffset |= Int(delta[idx]) << 24; idx += 1 }
                if (opcode & 0x10) != 0 { cpSize |= Int(delta[idx]); idx += 1 }
                if (opcode & 0x20) != 0 { cpSize |= Int(delta[idx]) << 8; idx += 1 }
                if (opcode & 0x40) != 0 { cpSize |= Int(delta[idx]) << 16; idx += 1 }
                if cpSize == 0 { cpSize = 0x10000 }

                guard cpOffset >= 0, cpSize >= 0, cpOffset + cpSize <= base.count else { throw DeltaError.outOfBounds }
                output.append(base.subdata(in: cpOffset..<(cpOffset+cpSize)))
            } else if opcode != 0 {
                // insert literal
                let insertSize = opcode & 0x7f
                guard idx + insertSize <= delta.count else { throw DeltaError.outOfBounds }
                output.append(delta.subdata(in: idx..<(idx+insertSize)))
                idx += insertSize
            } else {
                throw DeltaError.invalidHeader
            }
        }

        guard output.count == targetSize else { throw DeltaError.sizeMismatch }
        return output
    }
}

// MARK: - Private
private extension DeltaResolver {
    func readGitVarInt(_ data: Data, start: inout Int) -> Int {
        var result = 0
        var shift = 0
        while start < data.count {
            let b = Int(data[start])
            start += 1
            result |= (b & 0x7f) << shift
            if (b & 0x80) == 0 { break }
            shift += 7
        }
        return result
    }
}

enum DeltaError: LocalizedError {
    case invalidHeader, sizeMismatch, outOfBounds

    var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return "Invalid header"
        case .sizeMismatch:
            return "Size mismatch"
        case .outOfBounds:
            return "Index out of bounds"
        }
    }
}
