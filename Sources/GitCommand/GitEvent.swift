import Foundation

public enum GitEvent {
    case pushed(remote: String, branch: String?)
    case fetched(remote: String)
    case pulled(remote: String)

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
    case conflictResolved(path: String)
    case revertedCommit(hash: String)
    case cherryPickCompleted
    case resetCompleted(mode: ResetMode)
    case rebaseCompleted

    case stashed(id: String)
    case stashApplied
    case stashPopped(id: String)
    case stashDropped(id: String)

    case cherryPickContinued
    case mergeContinued
    case revertContinued
    case rebaseContinued

    case cherryPickAborted
    case mergeAborted
    case revertAborted
    case rebaseAborted

    case workflowCompleted(name: String)
}
