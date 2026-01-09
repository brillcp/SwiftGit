import Foundation

public enum GitCommand: Sendable {
    // MARK: - Staging
    case add(path: String)
    case addAll
    case reset(path: String)
    case resetAll

    // MARK: - Commits
    case commit(message: String, author: String?)

    // MARK: - Branches
    case checkout(branch: String, create: Bool = false)
    case deleteBranch(name: String, force: Bool = false)

    // MARK: - Working Tree
    case restore(path: String)
    case restoreAll
    case resetHardHEAD
    case clean(force: Bool, directories: Bool)

    // MARK: - Stash
    case stashPush(message: String?)
    case stashPop(index: Int?)
    case stashApply(index: Int?)
    case stashDrop(index: Int)

    // MARK: - History Manipulation
    case cherryPick(commitHash: String)
    case revert(commitHash: String, noCommit: Bool)

    // MARK: - Conflict Resolution
    case mergeAbort
    case cherryPickAbort
    case revertAbort

    // MARK: - Diff & Patches
    case diff(path: String, staged: Bool)
    case diffTree(commitId: String)
    case diffCommits(from: String, to: String, path: String)
    case showFile(commitId: String, path: String)
    case applyPatch(cached: Bool)
}

extension GitCommand {
    var arguments: [String] {
        switch self {
        // MARK: - Staging
        case .add(let path):
            return ["add", "--", path]
        case .addAll:
            return ["add", "--all"]
        case .reset(let path):
            return ["reset", "HEAD", "--", path]
        case .resetAll:
            return ["reset", "HEAD", "--", "."]

        // MARK: - Commits
        case .commit(let message, let author):
            var args = ["commit", "-m", message]
            if let author {
                args += ["--author", author]
            }
            return args

        // MARK: - Branches
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

        // MARK: - Working Tree
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

        // MARK: - Stash
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

        // MARK: - History Manipulation
        case .cherryPick(let commitHash):
            return ["cherry-pick", commitHash]
        case .revert(let commitHash, let noCommit):
            var args = ["revert"]
            if noCommit {
                args.append("--no-commit")
            }
            args.append(commitHash)
            return args

        // MARK: - Conflict Resolution
        case .mergeAbort:
            return ["merge", "--abort"]
        case .cherryPickAbort:
            return ["cherry-pick", "--abort"]
        case .revertAbort:
            return ["revert", "--abort"]

        // MARK: - Diff & Patches
        case .diff(let path, let staged):
            if staged {
                return ["diff", "--cached", path]
            } else {
                return ["diff", path]
            }
        case .diffTree(let commitId):
            return ["diff-tree", "--no-commit-id", "--name-status", "-r", "-M", commitId]
        case .diffCommits(let from, let to, let path):
            return ["diff", from, to, "--", path]
        case .showFile(let commitId, let path):
            return ["show", "\(commitId):\(path)"]
        case .applyPatch(let cached):
            var args = ["apply"]
            if cached {
                args.append("--cached")
            }
            args.append("--ignore-whitespace")
            args.append("--unidiff-zero")
            args.append("--whitespace=nowarn")
            return args
        }
    }
}
