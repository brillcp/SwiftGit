import Foundation

public enum GitCommand: Sendable {
    case add(path: String)
    case addAll  // For "stage all"
    case reset(path: String)
    case resetAll  // For "unstage all"
    case commit(message: String, author: String?)
    case checkout(branch: String, create: Bool = false)
    case applyPatch(cached: Bool)
    case restore(path: String)
    case restoreAll
}

extension GitCommand {
    var arguments: [String] {
        switch self {
        case .add(let path):
            return ["add", "--", path]
        case .addAll:
            return ["add", "--all"]
        case .reset(let path):
            return ["reset", "HEAD", "--", path]
        case .resetAll:
            return ["reset", "HEAD"]
        case .commit(let message, let author):
            var args = ["commit", "-m", message]
            if let author {
                args += ["--author", author]
            }
            return args
        case .checkout(let branch, let create):
            var args = ["checkout"]
            if create {
                args.append("-b")
            }
            args.append(branch)
            return args
        case .applyPatch(let cached):
            var args = ["apply"]
            if cached {
                args.append("--cached")
            }
            args.append("--ignore-whitespace")
            args.append("--unidiff-zero")
            args.append("--whitespace=nowarn")
            return args
        case .restore(let path):
            return ["restore", "--", path]
        case .restoreAll:
            return ["restore", "."]
        }
    }
}
