import Foundation

protocol DeltaResolverProtocol {
    /// Apply delta instructions to base data
    func apply(delta: Data, to base: Data) throws -> Data
    
    /// Resolve a delta chain (for OFS_DELTA and REF_DELTA)
    func resolveChain(
        object: PackObject,
        resolver: (String) throws -> Data // callback to get base object
    ) throws -> Data
}
