import Foundation

public enum GitCommand: Sendable {
    case add(paths: [String])
    case addAll  // For "stage all"
    case reset(paths: [String])
    case resetAll  // For "unstage all"
    case commit(message: String, author: String?)
    case applyPatch(patchPath: String, cached: Bool)
//    case checkout(branch: String)
//    case stash(message: String?)
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
        case .applyPatch(let patchPath, let cached):
            // Apply a patch file
            // --cached means apply to index (staging area)
            // without --cached applies to working directory
            var args = ["apply"]
            if cached {
                args.append("--cached")
            }
            args.append(patchPath)
            return args
        }
    }
}
