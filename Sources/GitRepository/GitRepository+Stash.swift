import Foundation

extension GitRepository: StashReadable {
    public func getStashes() async throws -> [Stash] {
        try await refReader.getStashes()
    }
}

// MARK: - StashManageable
extension GitRepository: StashManageable {
    public func stashPush(message: String?) async throws {}
    public func stashPop(index: Int?) async throws {}
    public func stashApply(index: Int?) async throws {}
    public func stashDrop(index: Int) async throws {}
}
