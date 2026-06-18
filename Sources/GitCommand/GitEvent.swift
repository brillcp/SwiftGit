import Foundation

public enum GitEvent: Sendable {
    case startPushing(remote: String, branch: String?)
    case startPulling(remote: String)
    case startFetching(remote: String)
    case startMerging(branch: String)
    case startRebasing
    case startCherryPicking
    case startResetting(mode: ResetMode)
    case startReverting(hash: String)
    case startContinuingOperation
    case startAbortingOperation
    case startSkippingOperation
    case startDeletingRemoteBranch(name: String)

    case pushed(remote: String, branch: String?)
    case fetched(remote: String)
    case pulled(remote: String)
    case remoteAdded(name: String)

    case fileStaged(path: String)
    case fileUnstaged(path: String)
    case fileDiscarded(path: String)
    case allFilesStaged
    case allFilesUnstaged
    case allFilesDiscarded

    case hunkStaged(hunk: DiffHunk, path: String)
    case hunkUnstaged(hunk: DiffHunk, path: String)
    case hunkDiscarded(hunk: DiffHunk, path: String)

    case committed(hash: String)
    case branchChanged(name: String)
    case branchDeleted(name: String)
    case revertedCommit(hash: String)
    case cherryPickCompleted
    case resetCompleted(mode: ResetMode)
    case rebaseCompleted
    case mergeCompleted(branch: String)

    case stashed(id: String)
    case stashApplied
    case stashPopped(id: String)
    case stashDropped(id: String)

    case cherryPickContinued
    case mergeContinued
    case revertContinued
    case rebaseContinued
    case rebaseSkipped

    case cherryPickAborted
    case mergeAborted
    case revertAborted
    case rebaseAborted

    case tagCreated(name: String)
    case tagDeleted(name: String)
    case tagPushed(name: String, remote: String)
    case ignoreUpdated(pattern: String)
}
