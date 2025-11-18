import Foundation

public enum RefType: Sendable {
    case localBranch, remoteBranch, stash, tag
}

public struct GitRef: Sendable {
    public let name: String
    public let hash: String
    public let type: RefType
}
