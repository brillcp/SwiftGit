import Foundation

public enum GitCommand: Sendable {
    case add(paths: [String])
    case reset(paths: [String])
    case commit(message: String, author: String?)
    case checkout(branch: String)
    case stash(message: String?)
}
