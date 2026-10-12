import Foundation

public protocol GitRepositoryProtocol:
    CommitReadable,
    CommitWritable,
    BranchReadable,
    BranchWritable,
    RefReadable,
    DiffReadable,
    WorkingTreeReadable,
    StagingWritable,
    DiscardWritable,
    IgnoreWritable,
    StashReadable,
    StashWritable,
    CherryPickWritable,
    RevertWritable,
    ConflictReadable,
    ConflictWritable,
    MergeWritable,
    ResetWritable,
    RebaseWritable,
    RemoteWritable,
    TagWritable
{
    /// The URL of the repository
    var url: URL { get }

    /// A fresh stream of repository events, starting with the next one
    /// emitted. Every caller gets an independent stream; stop iterating (or
    /// cancel the consuming task) to unsubscribe. `nonisolated` so callers on
    /// other actors can subscribe without an actor hop.
    nonisolated func events() -> AsyncStream<GitEvent>

    /// Initialize a repository at the given URL
    init(url: URL, cache: ObjectCacheProtocol)

    /// Run a git workflow with multiple commands in a row
    func executeWorkflow(_ workflow: GitWorkflow) async throws
}
