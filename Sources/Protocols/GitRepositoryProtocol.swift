import Foundation
import Combine

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
    RevertManageable,
    ConflictManageable
{
    /// The URL of the repository
    var url: URL { get }

    var events: AnyPublisher<GitEvent, Never> { get }

    /// Initialize a repository at the given URL
    init(url: URL, cache: ObjectCacheProtocol)
}
