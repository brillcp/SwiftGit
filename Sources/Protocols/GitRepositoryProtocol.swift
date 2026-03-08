import Foundation
import Combine

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

    var events: AnyPublisher<GitEvent, Never> { get }

    /// Initialize a repository at the given URL
    init(url: URL, cache: ObjectCacheProtocol)

    /// Run a git workflow with multiple commands in a row
    func executeWorkflow(_ workflow: GitWorkflow) async throws
}
