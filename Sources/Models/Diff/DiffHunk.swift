import Foundation

public struct DiffHunk: Hashable, Sendable {
    let id: Int
    let header: String
    let lines: [DiffLine]
}
