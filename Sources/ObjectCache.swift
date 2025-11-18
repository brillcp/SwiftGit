import Foundation

enum CacheKey: Hashable {
    case commit(hash: String)
    case tree(hash: String)
    case blob(hash: String)
    case treePaths(hash: String)
    case refs
    case head
    case objectLocation(hash: String)
}

struct CacheStats {
    let hits: Int
    let misses: Int
    let evictions: Int
    let currentSize: Int
    let memoryUsage: Int // bytes
}

protocol ObjectCacheProtocol {
    /// Get an object from cache
    func get<T>(_ key: CacheKey) -> T?
    
    /// Store an object in cache
    func set<T>(_ key: CacheKey, value: T)
    
    /// Remove an object from cache
    func remove(_ key: CacheKey)
    
    /// Check if key exists without retrieving value
    func contains(_ key: CacheKey) -> Bool
    
    /// Clear all cached objects
    func clear()
    
    /// Clear objects matching a predicate
    func clear(where predicate: (CacheKey) -> Bool)
    
    /// Get current cache statistics
    func stats() -> CacheStats
}
