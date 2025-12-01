import Foundation

public enum GitCommand: Sendable {
    case add(paths: [String])
    case reset(paths: [String])
    case commit(message: String, author: String?)
//    case checkout(branch: String)
//    case stash(message: String?)
}

extension GitCommand {
    var arguments: [String] {
        switch self {
        case .add(let paths):
            return ["add", "--"] + paths
        case .reset(let paths):
            return ["reset", "HEAD", "--"] + paths
        case .commit(let message, let author):
            var args = ["commit", "-m", message]
            if let author = author {
                args += ["--author", author]
            }
            return args
        }
    }
}
