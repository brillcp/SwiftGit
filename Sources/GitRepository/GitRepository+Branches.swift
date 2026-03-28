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
extension GitRepository: BranchWritable {
    public func push(
        remote: String? = nil,
        branch: String? = nil,
        setUpstream: Bool = false,
        force: Bool = false
    ) async throws {
        let result = try await commandRunner.run(
            .push(remote: remote, branch: branch, setUpstream: setUpstream, force: force)
        )

        guard result.exitCode == 0 else {
            let output = result.stderr + result.stdout

            if output.contains("failed to push") || output.contains("rejected") {
                throw GitError.pushRejected(reason: result.stderr)
            }
            if output.contains("no upstream") || output.contains("set-upstream") {
                throw GitError.noUpstream
            }
            if output.contains("authentication") || output.contains("denied") {
                throw GitError.authenticationFailed
            }

            throw GitError.pushFailed
        }

        await cache.remove(.refs)
        eventSubject.send(.pushed(remote: remote ?? "origin", branch: branch))
    }

    public func checkoutBranch(_ name: String, createNew: Bool) async throws {
        if !createNew {
            let status = try await getWorkingTreeStatus()
            guard status.files.isEmpty else {
                throw GitError.uncommittedChanges
            }
        }

        let result = try await commandRunner.run(
            .checkout(branch: name, create: createNew)
        )

        guard result.exitCode == 0 else {
            throw GitError.checkoutFailed(branch: name)
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await workingTree.invalidateIndexCache()
        eventSubject.send(.branchChanged(name: name))
    }

    public func deleteBranch(_ name: String, force: Bool) async throws {
        if let currentBranch = try await getHEADBranch(), currentBranch == name {
            throw GitError.cannotDeleteCurrentBranch
        }

        if protectedBranches.contains(name) {
            throw GitError.cannotDeleteProtectedBranch(name)
        }

        let result = try await commandRunner.run(
            .deleteBranch(name: name, force: force)
        )

        guard result.exitCode == 0 else {
            throw GitError.deleteBranchFailed(branch: name)
        }

        await cache.remove(.refs)
        eventSubject.send(.branchDeleted(name: name))
    }
}
