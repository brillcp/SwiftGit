import Foundation

extension GitRepository: BranchReadable {
    public func getBranches() async throws -> Branches {
        let refMap = try await refReader.getRefs()
        let allRefs = refMap.values.flatMap { $0 }

        return Branches(
            local: allRefs.filter { $0.type == .localBranch },
            remote: allRefs.filter { $0.type == .remoteBranch },
            current: try await refReader.getHEADBranch()
        )
    }    
}

// MARK: - BranchManageable
extension GitRepository: BranchManageable {
    public func checkout(branch: String, createNew: Bool) async throws {
        if !createNew {
            let status = try await getWorkingTreeStatus()
            guard status.files.isEmpty else {
                throw GitError.uncommittedChanges
            }
        }
        
        let result = try await commandRunner.run(
            .checkout(branch: branch, create: createNew),
            stdin: nil,
            in: url
        )
        
        guard result.exitCode == 0 else {
            let action = createNew ? "create and checkout" : "checkout"
            throw GitError.checkoutFailed(branch: branch, action: action, stderr: result.stderr)
        }
        
        // Invalidate caches after checkout
        await invalidateAllCaches()
    }

    public func deleteBranch(_ name: String, force: Bool) async throws {
        if let currentBranch = try await getHEADBranch(), currentBranch == name {
            throw GitError.cannotDeleteCurrentBranch
        }

        // Can't delete protected branches
        if protectedBranches.contains(name) {
            throw GitError.cannotDeleteProtectedBranch(name)
        }

        let result = try await commandRunner.run(
            .deleteBranch(name: name, force: force),
            stdin: nil,
            in: url
        )

        guard result.exitCode == 0 else {
            throw GitError.deleteBranchFailed(branch: name, stderr: result.stderr)
        }

        await cache.remove(.refs)
    }
}
