import Foundation

public enum GitChangeType: Hashable, Sendable {
    case added
    case modified
    case deleted
    case renamed(from: String)
    case untracked
}
