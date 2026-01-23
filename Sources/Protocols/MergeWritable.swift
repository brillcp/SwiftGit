import Foundation

/// A protocol for merging operations
public protocol MergeWritable: Actor {
    /// Merge the given branch
    func merge(branch: String, noFastForward: Bool) async throws
}
