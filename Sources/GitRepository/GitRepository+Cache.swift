import Foundation

extension GitRepository: CacheManageable {
    public func invalidateAllCaches() async {
        await workingTree.invalidateIndexCache()
        await cache.remove(.head)
        await cache.remove(.refs)
    }
}
