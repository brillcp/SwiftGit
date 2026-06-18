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

    public func getUpstream(for branch: String?) async throws -> Upstream? {
        let result = try await commandRunner.run(.revParseAbbrevUpstream(branch: branch))

        // Non-zero exit means no upstream is configured for this branch — git
        // prints "fatal: no upstream configured" to stderr. Surface as nil
        // rather than throwing, since "no upstream yet" is a normal state.
        guard result.exitCode == 0 else { return nil }

        let raw = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        // Output format is "<remote>/<branch>". Split on the FIRST slash —
        // the branch portion may itself contain slashes (e.g. "feature/foo").
        guard let slashIndex = raw.firstIndex(of: "/") else { return nil }
        let remote = String(raw[..<slashIndex])
        let branchName = String(raw[raw.index(after: slashIndex)...])
        guard !remote.isEmpty, !branchName.isEmpty else { return nil }

        return Upstream(remote: remote, branch: branchName)
    }

    public func getAheadBehind(local: String, upstream: String) async throws -> (ahead: Int, behind: Int) {
        let result = try await commandRunner.run(
            .revListLeftRightCount(local: local, upstream: upstream)
        )

        guard result.exitCode == 0 else { return (0, 0) }

        // Output is one line: "<ahead>\t<behind>". Anything else means git
        // produced unexpected output — fall back to (0, 0) rather than throw.
        let parts = result.stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "\t" || $0 == " " })

        guard parts.count == 2,
              let ahead = Int(parts[0]),
              let behind = Int(parts[1])
        else { return (0, 0) }

        return (ahead, behind)
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
        eventSubject.send(.startPushing(remote: remote ?? "origin", branch: branch))

        let result = try await backgroundRunner.run(
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

    public func deleteRemoteBranch(_ name: String) async throws {
        let components = name.split(separator: "/", maxSplits: 1)
        let remote = components.count > 1 ? String(components[0]) : "origin"
        let branch = components.count > 1 ? String(components[1]) : name

        let result = try await backgroundRunner.run(
            .deleteRemoteBranch(remote: remote, branch: branch)
        )

        guard result.exitCode == 0 else {
            let output = result.stderr + result.stdout
            if output.contains("authentication") || output.contains("denied") {
                throw GitError.authenticationFailed
            }
            throw GitError.deleteRemoteBranchFailed(branch: name)
        }

        await cache.remove(.refs)
        eventSubject.send(.branchDeleted(name: name))
    }
}
