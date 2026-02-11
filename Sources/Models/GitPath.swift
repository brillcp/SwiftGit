import Foundation

enum GitPath: String {
    case git = ".git"
    case objects
    case pack
    case index
    case packedRefs = "packed-refs"
    case head = "HEAD"
    case mergeHead = "MERGE_HEAD"
    case cherryPickHead = "CHERRY_PICK_HEAD"
    case revertHead = "REVERT_HEAD"
    case rebaseHead = "REBASE_HEAD"
    case rebaseMerge = "rebase-merge"
    case rebaseApply = "rebase-apply"
}