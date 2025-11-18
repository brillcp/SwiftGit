import Foundation

protocol BlobParserProtocol: ObjectParserProtocol where Output == Blob {}

final class BlobParser: BlobParserProtocol {
    func parse(hash: String, data: Data) throws -> Blob {
        Blob(id: hash, data: data)
    }
}
