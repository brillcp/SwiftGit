import Foundation

enum RefType {
    case localBranch, remoteBranch, stash, tag
}

struct GitRef {
    let name: String
    let hash: String
    let type: RefType
}
