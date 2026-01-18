import Foundation

public protocol MergeWritable: Actor {
    /// Continue an ongoing merge
    func mergeContinue() async throws

    /// Abort current merge
    func mergeAbort() async throws
}
