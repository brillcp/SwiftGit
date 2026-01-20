import Foundation

extension GitRepository: WorkingTreeReadable {
    public func getWorkingTreeStatus() async throws -> WorkingTreeStatus {
        try await workingTree.workingTreeStatus()
    }
}
