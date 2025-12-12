import Foundation

/// Protocol for cache management
public protocol CacheManageable: Actor {
    /// Invalidate all caches
    func invalidateAllCaches() async
}
