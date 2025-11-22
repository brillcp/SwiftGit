import Foundation

public enum CacheKey: Hashable {
    case commit(hash: String)
    case tree(hash: String)
    case blob(hash: String)
    case treePaths(hash: String)
    case objectLocation(hash: String)
    case refs
    case head
    case indexSnapshot(url: URL)
    case fileHash(identity: FileIdentity)
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

public actor ObjectCache {
    private var storage: [CacheKey: CacheEntry] = [:]
    private var accessOrder: LinkedList<CacheKey> = LinkedList()
    
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
    public func get<T>(_ key: CacheKey) -> T? {
        guard let entry = storage[key] else {
            missCount += 1
            return nil
        }
        
        // Update access time and move to front (most recently used)
        storage[key]?.lastAccessed = Date()
        accessOrder.moveToFront(key)
        
        hitCount += 1
        return entry.value as? T
    }
    
    public func set<T>(_ key: CacheKey, value: T) {
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
            accessOrder.moveToFront(key)
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
    
    public func remove(_ key: CacheKey) {
        if let entry = storage[key] {
            currentMemoryUsage -= entry.estimatedSize
            storage.removeValue(forKey: key)
            accessOrder.remove(key)
        }
    }
    
    public func contains(_ key: CacheKey) -> Bool {
        storage[key] != nil
    }
    
    public func clear() {
        storage.removeAll()
        accessOrder.removeAll()
        currentMemoryUsage = 0
    }
    
    public func clear(where predicate: (CacheKey) -> Bool) {
        let keysToRemove = storage.keys.filter(predicate)
        for key in keysToRemove {
            if let entry = storage[key] {
                currentMemoryUsage -= entry.estimatedSize
                storage.removeValue(forKey: key)
                accessOrder.remove(key)
            }
        }
    }
    
    public func stats() -> CacheStats {
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
        // Evict until we're under both limits
        while storage.count > maxObjects || currentMemoryUsage > maxMemory {
            guard let lruKey = accessOrder.first else { break }
            
            if let entry = storage[lruKey] {
                currentMemoryUsage -= entry.estimatedSize
                storage.removeValue(forKey: lruKey)
                accessOrder.removeFirst()
                evictionCount += 1
            }
        }
    }
    
    func estimateSize(_ value: Any) -> Int {
        switch value {
        case let commit as Commit:
            return commit.title.count + commit.body.count + 200
        case let tree as Tree:
            return tree.entries.count * 100
        case let blob as Blob:
            return blob.data.count
        case let dict as [String: String]:
            return dict.keys.reduce(0) { $0 + $1.count } + dict.values.reduce(0) { $0 + $1.count }
        case let array as [GitRef]:
            return array.count * 100
        case let string as String:
            return string.count
        case let tuple as (snapshot: GitIndexSnapshot, modDate: Date):
            return tuple.snapshot.entries.count * 150
        default:
            return 500
        }
    }
}

// MARK: - Private linked list
private class LinkedList<T: Hashable> {
    private class Node {
        let value: T
        var prev: Node?
        var next: Node?
        
        init(value: T) {
            self.value = value
        }
    }
    
    private var head: Node?
    private var tail: Node?
    private var nodeMap: [T: Node] = [:]
    
    var first: T? {
        head?.value
    }
    
    func append(_ value: T) {
        let node = Node(value: value)
        nodeMap[value] = node
        
        if head == nil {
            head = node
            tail = node
        } else {
            tail?.next = node
            node.prev = tail
            tail = node
        }
    }
    
    func remove(_ value: T) {
        guard let node = nodeMap[value] else { return }
        
        if node === head {
            head = node.next
        }
        if node === tail {
            tail = node.prev
        }
        
        node.prev?.next = node.next
        node.next?.prev = node.prev
        
        nodeMap.removeValue(forKey: value)
    }
    
    func removeFirst() {
        guard let head = head else { return }
        remove(head.value)
    }
    
    func moveToFront(_ value: T) {
        guard let node = nodeMap[value], node !== tail else { return }
        
        // Remove from current position
        if node === head {
            head = node.next
        }
        node.prev?.next = node.next
        node.next?.prev = node.prev
        
        // Move to tail (most recently used)
        tail?.next = node
        node.prev = tail
        node.next = nil
        tail = node
    }
    
    func removeAll() {
        head = nil
        tail = nil
        nodeMap.removeAll()
    }
}
