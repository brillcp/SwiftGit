import Foundation

public enum RefType: Sendable {
    case localBranch, remoteBranch, stash, tag
}

public struct GitRef: Sendable {
    let name: String
    let hash: String
    let type: RefType
}
