import Foundation

public protocol BlobParserProtocol: ObjectParserProtocol where Output == Blob {}

// MARK: -
public final class BlobParser {
    public init() {}
}

// MARK: - BlobParserProtocol
extension BlobParser: BlobParserProtocol {
    public func parse(hash: String, data: Data) throws -> Blob {
        Blob(id: hash, data: data)
    }
}
