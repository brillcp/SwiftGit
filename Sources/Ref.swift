import Foundation

enum RefType {
    case localBranch, remoteBranch, stash, tag
}

struct Ref {
    let name: String
    let hash: String
    let type: RefType
}
