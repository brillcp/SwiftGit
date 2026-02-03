import Foundation
import Collections

extension GitRepository: RefReadable {
    public func getRefs() async throws -> OrderedDictionary<String, [GitRef]> {
        try await refReader.getRefs()
    }
}