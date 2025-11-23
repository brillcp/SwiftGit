import Foundation

public enum RefType: Sendable {
    case localBranch, remoteBranch, stash, tag
}

public struct GitRef: Hashable, Sendable {
    public let name: String
    public let hash: String
    public let type: RefType

    public init(name: String, hash: String, type: RefType) {
        self.name = name
        self.hash = hash
        self.type = type
    }
}

extension GitRef: Identifiable {
    public var id: String {
        hash
    }
}
