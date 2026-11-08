import Foundation

extension GitRepository: TagWritable {
    public func createTag(name: String, ref: String, message: String?) async throws {
        let result = try await commandRunner.run(.createTag(name: name, ref: ref, message: message))

        guard result.exitCode == 0 else {
            throw GitError.tagCreationFailed(name: name)
        }

        await cache.remove(.refs)
        eventPublisher.send(.tagCreated(name: name))
    }

    public func deleteTag(name: String) async throws {
        let result = try await commandRunner.run(.deleteTag(name: name))

        guard result.exitCode == 0 else {
            throw GitError.tagDeletionFailed(name: name)
        }

        await cache.remove(.refs)
        eventPublisher.send(.tagDeleted(name: name))
    }

    public func pushTag(name: String, remote: String = "origin", force: Bool = false) async throws {
        let result = try await backgroundRunner.run(.pushTag(remote: remote, name: name, force: force))

        guard result.exitCode == 0 else {
            let output = result.stderr + result.stdout
            if output.contains("authentication") || output.contains("denied") {
                throw GitError.authenticationFailed
            }
            if output.contains("rejected") {
                throw GitError.pushRejected(reason: result.stderr)
            }
            throw GitError.pushFailed
        }

        eventPublisher.send(.tagPushed(name: name, remote: remote))
    }

    public func moveTag(name: String, to ref: String) async throws {
        let info = try await commandRunner.run(.tagInfo(name: name))
        let fields = info.stdout.split(separator: "\0", maxSplits: 1, omittingEmptySubsequences: false)
        guard info.exitCode == 0, let objectType = fields.first, !objectType.isEmpty else {
            throw GitError.tagMoveFailed(name: name)
        }

        // An annotated tag points at a tag object; a lightweight tag points straight at a commit.
        let message = objectType == "tag"
            ? fields.dropFirst().first.map { String($0).trimmingCharacters(in: .newlines) }
            : nil
        let result = try await commandRunner.run(.moveTag(name: name, ref: ref, message: message))

        guard result.exitCode == 0 else {
            throw GitError.tagMoveFailed(name: name)
        }

        await cache.remove(.refs)
        eventPublisher.send(.tagMoved(name: name, ref: ref))
    }

    public func deleteRemoteTag(name: String, remote: String = "origin") async throws {
        let result = try await backgroundRunner.run(.deleteRemoteTag(remote: remote, name: name))

        guard result.exitCode == 0 else {
            let output = result.stderr + result.stdout
            if output.contains("authentication") || output.contains("denied") {
                throw GitError.authenticationFailed
            }
            throw GitError.tagDeletionFailed(name: name)
        }

        await cache.remove(.refs)
        eventPublisher.send(.tagDeleted(name: name))
    }
}
