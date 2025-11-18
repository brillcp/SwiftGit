import Foundation

protocol ObjectParserProtocol {
    associatedtype Output
    
    /// Parse raw object data
    func parse(hash: String, data: Data) throws -> Output
}

protocol BlobParserProtocol: ObjectParserProtocol where Output == Blob {}
