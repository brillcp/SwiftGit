import Foundation

/// Protocol for cache management
public protocol CacheWritable: Actor {
    /// Invalidate all caches
    func invalidateAllCaches() async
}
