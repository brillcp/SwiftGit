import Foundation

extension GitRepository: RefReadable {
    public func getRefs() async throws -> [String : [GitRef]] {
        try await refReader.getRefs()
    }
}