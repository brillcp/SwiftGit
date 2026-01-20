import Foundation

extension GitRepository: CacheWritable {
    public func invalidateAllCaches() async {
        await workingTree.invalidateIndexCache()
        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.clearDiffCaches()
    }
}
