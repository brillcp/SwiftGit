import Foundation
import Collections

public enum CacheKey: Hashable, Sendable {
    case commit(hash: String)
    case refs
    case head
    case stashes
    case indexSnapshot(url: URL)
    case fileDiff(commitId: String, path: String)
}

public struct CacheStats {
    let hits: Int
    let misses: Int
    let evictions: Int
    let currentSize: Int
    let memoryUsage: Int // bytes
}

public protocol ObjectCacheProtocol: Actor {
    /// Get an object from cache
    func get<T>(_ key: CacheKey) async -> T?

    /// Store an object in cache
    func set<T>(_ key: CacheKey, value: T) async

    /// Remove an object from cache
    func remove(_ key: CacheKey) async

    /// Check if key exists without retrieving value
    func contains(_ key: CacheKey) async -> Bool

    /// Clear all cached objects
    func clear() async

    /// Clear objects matching a predicate
    func clear(where predicate: (CacheKey) -> Bool) async

    /// Get current cache statistics
    func stats() async -> CacheStats
}

public actor ObjectCache {
    private var storage: [CacheKey: CacheEntry] = [:]
    private var accessOrder: OrderedSet<CacheKey> = []

    private var hitCount: Int = 0
    private var missCount: Int = 0
    private var evictionCount: Int = 0
    private var currentMemoryUsage: Int = 0

    private let maxObjects: Int
    private let maxMemory: Int

    public init(maxObjects: Int = 5000, maxMemory: Int = 200_000_000) {
        self.maxObjects = maxObjects
        self.maxMemory = maxMemory
    }
}

// MARK: - ObjectCacheProtocol
extension ObjectCache: ObjectCacheProtocol {
    public func get<T>(_ key: CacheKey) async -> T? {
        guard var entry = storage[key] else {
            missCount += 1
            return nil
        }

        hitCount += 1
        // Move to end (most recently used)
        accessOrder.remove(key)
        accessOrder.append(key)
        entry.lastAccessed = .now
        storage[key] = entry
        return entry.value as? T
    }

    public func set<T>(_ key: CacheKey, value: T) async {
        let estimatedSize = estimateSize(value)

        // If object already exists, update it
        if let existingEntry = storage[key] {
            currentMemoryUsage -= existingEntry.estimatedSize
            currentMemoryUsage += estimatedSize
            storage[key] = CacheEntry(
                value: value,
                lastAccessed: Date(),
                estimatedSize: estimatedSize
            )
            // Move to end (most recently used)
            accessOrder.remove(key)
            accessOrder.append(key)
            return
        }

        // Add new entry
        storage[key] = CacheEntry(
            value: value,
            lastAccessed: Date(),
            estimatedSize: estimatedSize
        )
        accessOrder.append(key)
        currentMemoryUsage += estimatedSize

        // Evict if needed
        evictIfNeeded()
    }

    public func remove(_ key: CacheKey) async {
        guard let entry = storage[key] else { return }

        currentMemoryUsage -= entry.estimatedSize
        storage.removeValue(forKey: key)
        accessOrder.remove(key)
    }

    public func contains(_ key: CacheKey) async -> Bool {
        storage[key] != nil
    }

    public func clear() async {
        storage.removeAll()
        accessOrder.removeAll()
        currentMemoryUsage = 0
    }

    public func clear(where predicate: (CacheKey) -> Bool) async {
        let keysToRemove = accessOrder.filter(predicate)

        for key in keysToRemove {
            if let entry = storage[key] {
                currentMemoryUsage -= entry.estimatedSize
                storage.removeValue(forKey: key)
                accessOrder.remove(key)
            }
        }
    }

    public func stats() async -> CacheStats {
        CacheStats(
            hits: hitCount,
            misses: missCount,
            evictions: evictionCount,
            currentSize: storage.count,
            memoryUsage: currentMemoryUsage
        )
    }
}

// MARK: - Private Helpers
private extension ObjectCache {
    struct CacheEntry {
        let value: Any
        var lastAccessed: Date
        let estimatedSize: Int
    }

    func evictIfNeeded() {
        // Evict least recently used (first element) until we're under both limits
        while storage.count > maxObjects || currentMemoryUsage > maxMemory {
            guard let lruKey = accessOrder.first else { break }

            if let entry = storage[lruKey] {
                currentMemoryUsage -= entry.estimatedSize
                storage.removeValue(forKey: lruKey)
                accessOrder.remove(at: 0)
                evictionCount += 1
            }
        }
    }

    func estimateSize(_ value: Any) -> Int {
        switch value {
        case let commit as Commit:
            return commit.title.count + commit.body.count + 200
        case let dict as [String: String]:
            return dict.keys.reduce(0) { $0 + $1.count } + dict.values.reduce(0) { $0 + $1.count }
        case let array as [GitRef]:
            return array.count * 100
        case let string as String:
            return string.count
        case let tuple as (snapshot: GitIndexSnapshot, modDate: Date):
            return tuple.snapshot.entryCount * 150
        case let hunks as [DiffHunk]:
            var totalSize = 0
            for hunk in hunks {
                var hunkSize = 100
                for line in hunk.lines {
                    for segment in line.segments {
                        hunkSize += segment.text.count
                    }
                }
                totalSize += hunkSize
            }
            return totalSize
        default:
            return 500
        }
    }
}
