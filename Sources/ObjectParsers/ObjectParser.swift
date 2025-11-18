import Foundation

public protocol ObjectParserProtocol {
    associatedtype Output
    
    /// Parse raw object data
    func parse(hash: String, data: Data) throws -> Output
}
