
import Foundation

public protocol TreeParserProtocol: ObjectParserProtocol where Output == Tree {}

// MARK: -
public final class TreeParser {
    public init() {}
}

// MARK: - TreeParserProtocol
extension TreeParser: TreeParserProtocol {
    public func parse(hash: String, data: Data) throws -> Tree {
        var entries: [Tree.Entry] = []
        var index = data.startIndex
        let end = data.endIndex

        while index < end {
            // Read mode up to space
            let modeStart = index
            while index < end, data[index] != 0x20 { index = data.index(after: index) }
            guard index < end else { throw ParseError.malformedTree }
            let modeData = data[modeStart..<index]
            index = data.index(after: index) // skip space

            // Read name up to NUL
            let nameStart = index
            while index < end, data[index] != 0x00 { index = data.index(after: index) }
            guard index < end else { throw ParseError.malformedTree }
            let nameData = data[nameStart..<index]
            index = data.index(after: index)

            // Read 20-byte object id
            guard data.distance(from: index, to: end) >= 20 else { throw ParseError.malformedTree }
            let hashData = data[index..<data.index(index, offsetBy: 20)]
            index = data.index(index, offsetBy: 20)

            // Convert to displayable fields
            let mode = String(decoding: modeData, as: UTF8.self)
            let name = String(decoding: nameData, as: UTF8.self)
            let entryHash = hashData.toHexString()
            entries.append(
                Tree.Entry(
                    mode: mode,
                    type: .tree,
                    hash: entryHash,
                    name: name,
                    path: ""
                )
            )
        }
        return Tree(id: hash, entries: entries)
    }
}
