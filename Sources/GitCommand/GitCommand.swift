import Foundation

public enum GitCommand: Sendable {
    case add(path: String)
    case addAll  // For "stage all"
    case reset(path: String)
    case resetAll  // For "unstage all"
    case commit(message: String, author: String?)
    case checkout(branch: String, create: Bool = false)
    case deleteBranch(name: String, force: Bool = false)
    case applyPatch(cached: Bool)
    case restore(path: String)
    case restoreAll
    case resetHardHEAD
    case clean(force: Bool, directories: Bool)
    case stashPush(message: String?)
    case stashPop(index: Int?)
    case stashApply(index: Int?)
    case stashDrop(index: Int)
    case cherryPick(commitHash: String)
    case revert(commitHash: String, noCommit: Bool)
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
        case .deleteBranch(let name, let force):
            var args = ["branch"]
            args.append(force ? "-D" : "-d")
            args.append(name)
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
        case .resetHardHEAD:
            return ["reset", "--hard", "HEAD"]
        case .clean(let force, let directories):
            var args = ["clean"]
            if force { args.append("-f") }
            if directories { args.append("-d") }
            return args
        case .stashPush(let message):
            var args = ["stash", "push"]
            if let message = message {
                args += ["-m", message]
            }
            return args
        case .stashPop(let index):
            var args = ["stash", "pop"]
            if let index = index {
                args.append("stash@{\(index)}")
            }
            return args
        case .stashApply(let index):
            var args = ["stash", "apply"]
            if let index = index {
                args.append("stash@{\(index)}")
            }
            return args
        case .stashDrop(let index):
            return ["stash", "drop", "stash@{\(index)}"]
        case .cherryPick(let commitHash):
            return ["cherry-pick", commitHash]
        case .revert(let commitHash, let noCommit):
            var args = ["revert"]
            if noCommit {
                args.append("--no-commit")
            }
            args.append(commitHash)
            return args
        }
    }
}
