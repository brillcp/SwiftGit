import Foundation

extension GitRepository: WorkingTreeReadable {
    public func getWorkingTreeStatus() async throws -> WorkingTreeStatus {
        let snapshot = try await getRepoSnapshot()
        return try await workingTree.computeStatus(snapshot: snapshot)
    }
    
    public func getStagedChanges() async throws -> [String: WorkingTreeFile] {
        let snapshot = try await getRepoSnapshot()
        return try await workingTree.stagedChanges(snapshot: snapshot)
    }
    
    public func getUnstagedChanges() async throws -> [String: WorkingTreeFile] {
        try await workingTree.unstagedChanges()
    }
}
