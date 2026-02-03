import Foundation

fileprivate let commitFormat: String = "%H%x00%P%x00%T%x00%an%x00%ae%x00%at%x00%cn%x00%ce%x00%ct%x00%s%x00%b"

public enum GitCommand: Sendable {
    // MARK: - Remote
    case push(remote: String?, branch: String?, setUpstream: Bool, force: Bool)
    case fetch(remote: String?, prune: Bool)
    case pull(remote: String?, branch: String?)
    case merge(branch: String, noFastForward: Bool = true)

    // MARK: - Staging
    case add(path: String)
    case addAll
    case reset(path: String)
    case resetAll

    // MARK: - Commits
    case log(limit: Int)
    case showCommit(hash: String)
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
    case stashPushFile(path: String, message: String?)
    case stashPop(index: Int)
    case stashApply(index: Int)
    case stashDrop(index: Int)

    // MARK: - History Manipulation
    case resetToCommit(mode: ResetMode, target: String)
    case cherryPick(commitHash: String)
    case cherryPickSkip
    case revert(commitHash: String, noCommit: Bool)
    case rebase(onto: String)
    case cherryPickContinue
    case mergeContinue
    case revertContinue
    case rebaseContinue

    // MARK: - Conflict Resolution
    case mergeAbort
    case cherryPickAbort
    case revertAbort
    case rebaseAbort

    // MARK: - Diff & Patches
    case diff(path: String, staged: Bool, untracked: Bool, deleted: Bool)
    case showCommitFiles(commitId: String)
    case showFileDiff(commitId: String, path: String)
    case diffCommits(from: String, to: String, path: String)
    case diffFromEmpty(to: String, path: String)
    case showFile(commitId: String, path: String)
    case stashShow(ref: String)
    case applyPatch(patch: String, cached: Bool)

    // MARK: - Working Tree Status
    case status(porcelain: Bool)
    case lsFilesStaged

    // MARK: - Refs and HEAD
    case showRef
    case revParse(rev: String)
    case symbolicRef
    case stashList
    case showCommitDate(ref: String)
}

extension GitCommand {
    var stdinData: Data? {
        switch self {
        case .applyPatch(let patch, _):
            return patch.data(using: .utf8)
        default:
            return nil
        }
    }

    var arguments: [String] {
        switch self {
        // MARK: - Remote
        case .push(let remote, let branch, let setUpstream, let force):
            var args = ["push"]
            if force { args.append("--force") }
            if setUpstream { args.append("--set-upstream") }
            if let remote { args.append(remote) }
            if let branch { args.append(branch) }
            return args
        case .fetch(let remote, let prune):
            var args = ["fetch"]
            if let remote { args.append(remote) }
            if prune { args.append("--prune") }
            return args
        case .pull(let remote, let branch):
            var args = ["pull"]
            if let remote { args.append(remote) }
            if let branch { args.append(branch) }
            return args
        case .merge(let branch, let noFastForward):
            var args = ["merge", branch]
            if noFastForward {
                args.append("--no-ff")
            }
            args.append("-m")
            args.append("Merge \(branch)")
            return args

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
        case .log(let limit):
            return [
                "log",
                "--all",
                "--topo-order",
                "-n", "\(limit)",
                "--format=\(commitFormat)"
            ]
        case .showCommit(let hash):
            return [
                "show",
                "-s",
                "--format=\(commitFormat)",
                hash
            ]
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
            var args = ["stash", "push", "--include-untracked"]
            if let message {
                args += ["-m", message]
            }
            return args
        case .stashPushFile(let path, let message):
            var args = ["stash", "push"]
            if let message {
                args += ["-m", message]
            }
            args += ["--", path]
            return args
        case .stashPop(let index):
            return ["stash", "pop", String.stashId(for: index)]
        case .stashApply(let index):
            return ["stash", "apply", String.stashId(for: index)]
        case .stashDrop(let index):
            return ["stash", "drop", String.stashId(for: index)]

        // MARK: - History Manipulation
        case .resetToCommit(let mode, let target):
            return ["reset", mode.rawValue, target]
        case .cherryPick(let commitHash):
            return ["cherry-pick", commitHash]
        case .cherryPickSkip:
            return ["cherry-pick", "--skip"]
        case .revert(let commitHash, let noCommit):
            var args = ["revert"]
            if noCommit {
                args.append("--no-commit")
            }
            args.append(commitHash)
            return args
        case .rebase(let onto):
            return ["rebase", onto]
        case .cherryPickContinue:
            return ["cherry-pick", "--continue", "--no-edit"]
        case .mergeContinue:
            return ["merge", "--continue", "--no-edit"]
        case .revertContinue:
            return ["revert", "--continue", "--no-edit"]
        case .rebaseContinue:
            return ["rebase", "--continue"]

        // MARK: - Conflict Resolution
        case .mergeAbort:
            return ["merge", "--abort"]
        case .cherryPickAbort:
            return ["cherry-pick", "--abort"]
        case .revertAbort:
            return ["revert", "--abort"]
        case .rebaseAbort:
            return ["rebase", "--abort"]

        // MARK: - Diff & Patches
        case .diff(let path, let staged, let untracked, let deleted):
            var args = ["diff"]
            if deleted {
                args.append("HEAD")
                args.append("--")
                args.append(path)
                return args
            }
            if staged {
                args.append("--cached")
            }
            if untracked {
                args.append("--no-index")
                args.append("/dev/null")
            }
            args.append(path)
            return args
        case .showCommitFiles(let commitId):
            return ["show", "-z", "-M", "-m", "--name-status", "--pretty=", commitId]
        case .showFileDiff(let commitId, let path):
            return ["show", "-m", commitId, "--", path]
        case .diffCommits(let from, let to, let path):
            return ["diff", from, to, "--", path]
        case .diffFromEmpty(let to, let path):
            return ["diff", "4b825dc642cb6eb9a060e54bf8d69288fbee4904", to, "--", path]
        case .showFile(let commitId, let path):
            return ["show", "\(commitId):\(path)"]
        case .stashShow(let ref):
            return ["stash", "show", "--include-untracked", "--name-status", "--find-renames", ref]
        case .applyPatch(_, let cached):
            var args = ["apply"]
            if cached {
                args.append("--cached")
            }
            args.append("--ignore-whitespace")
            args.append("--unidiff-zero")
            args.append("--whitespace=nowarn")
            args.append("-")
            return args

        // MARK: - Working Tree Status
        case .status(let porcelain):
            var args = ["status"]
            if porcelain {
                args.append("--porcelain=v1")
            }
            args.append("-z")
            args.append("-uall")
            args.append("--find-renames")
            return args
        case .lsFilesStaged:
            return ["ls-files", "-z", "--stage"]

        // MARK: - Refs and HEAD
        case .showRef:
            return ["show-ref"]
        case .revParse(let rev):
            return ["rev-parse", "--verify", rev]
        case .symbolicRef:
            return ["symbolic-ref", "HEAD"]
        case .stashList:
            return ["stash", "list"]
        case .showCommitDate(let ref):
            return ["show", "-s", "--format=%at", ref]
        }
    }
}
