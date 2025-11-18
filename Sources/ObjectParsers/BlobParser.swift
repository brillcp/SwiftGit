import Foundation

protocol BlobParserProtocol: ObjectParserProtocol where Output == Blob {}

// MARK: -
final class BlobParser {}

// MARK: - BlobParserProtocol
extension BlobParser: BlobParserProtocol {
    func parse(hash: String, data: Data) throws -> Blob {
        Blob(id: hash, data: data)
    }
}
