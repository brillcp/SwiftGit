import Foundation

public protocol CherryPickWritable: Actor {
    /// Apply changes from a commit to the current branch
    func cherryPick(_ commitHash: String) async throws
}
