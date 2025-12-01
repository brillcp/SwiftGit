import Foundation

public enum GitCommand: Sendable {
    case add(paths: [String])
    case addAll  // For "stage all"
    case reset(paths: [String])
    case resetAll  // For "unstage all"
    case commit(message: String, author: String?)
    case applyPatch(cached: Bool)
}

extension GitCommand {
    var arguments: [String] {
        switch self {
        case .add(let paths):
            return ["add", "--"] + paths
        case .addAll:
            return ["add", "--all"]
        case .reset(let paths):
            return ["reset", "HEAD", "--"] + paths
        case .resetAll:
            return ["reset", "HEAD"]
        case .commit(let message, let author):
            var args = ["commit", "-m", message]
            if let author = author {
                args += ["--author", author]
            }
            return args
        case .applyPatch(let cached):
            var args = ["apply"]
            if cached {
                args.append("--cached")
            }
            return args
        }
    }
}
