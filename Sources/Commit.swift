import SwiftUI

struct Commit: Identifiable {
    let id: String
    let title: String
    let body: String
//    let author: Author
    let parents: [String]
    let tree: String
}

// MARK: - Equatable
extension Commit: Equatable {
    static func == (lhs: Commit, rhs: Commit) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: -
extension String {
    var shortHash: String {
        String(prefix(6))
    }
}
