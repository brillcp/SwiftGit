import Foundation

public protocol GitRepositoryProtocol:
    CommitReadable,
    CommitWritable,
    BranchReadable,
    BranchManageable,
    RefReadable,
    DiffReadable,
    WorkingTreeReadable,
    StagingManageable,
    DiscardManageable,
    StashReadable,
    StashManageable,
    ObjectReadable,
    CacheManageable,
    CherryPickManageable,
    RevertManageable
{
    /// The URL of the repository
    var url: URL { get }

    /// Initialize a repository at the given URL
    init(url: URL, cache: ObjectCacheProtocol)
}
