import Foundation

enum ObjectLocation {
    case loose(url: URL)
    case packed(location: PackObjectLocation)
}

protocol ObjectLocatorProtocol {
    /// Find where an object is stored (loose or packed)
    func locate(_ hash: String) async throws -> ObjectLocation?
    
    /// Check if object exists without determining location
    func exists(_ hash: String) async throws -> Bool
    
    /// Get all available object hashes
    func getAllHashes() async throws -> Set<String>
    
    /// Invalidate location cache (when repo changes)
    func invalidate()
}
