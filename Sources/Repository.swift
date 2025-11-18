import Foundation

protocol GitRepositoryProtocol {
    /// Repository URL
    var url: URL { get }
    
    // MARK: - Object Access
    
    /// Get a commit by hash (lazy loaded)
    func getCommit(_ hash: String) async throws -> Commit?
    
    /// Get a tree by hash (lazy loaded)
    func getTree(_ hash: String) async throws -> Tree?
    
    /// Get a blob by hash (lazy loaded)
    func getBlob(_ hash: String) async throws -> Blob?
    
    /// Stream a large blob without loading entirely into memory
    func streamBlob(_ hash: String) -> AsyncThrowingStream<Data, Error>
    
    // MARK: - Tree Walking
    
    /// Walk a tree recursively, calling visitor for each entry
    /// Visitor returns true to continue, false to stop
    func walkTree(_ treeHash: String, visitor: (Tree.Entry) async throws -> Bool) async throws
    
    /// Get all file paths in a tree (flattened)
    func getTreePaths(_ treeHash: String) async throws -> [String: String] // path -> blob hash
    
    // MARK: - References
    
    /// Get all refs (branches, tags, etc.)
    func getRefs() async throws -> [Ref]
    
    /// Get current HEAD commit hash
    func getHEAD() async throws -> String?
    
    /// Get HEAD branch name (nil if detached)
    func getHEADBranch() async throws -> String?
    
    // MARK: - History & Graph
    
    /// Get commit history starting from a commit
    func getHistory(from commitHash: String, limit: Int?) async throws -> [Commit]
    
    /// Check if an object exists (without loading it)
    func objectExists(_ hash: String) async throws -> Bool
}

// MARK: -
final class Repository {
    
}

// MARK: -
extension Repository {
    
}
