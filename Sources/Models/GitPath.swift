import Foundation

enum GitPath: String {
    case git = ".git"
    case objects
    case pack
    case index
    case packedRefs = "packed-refs"
    case head = "HEAD"
}
