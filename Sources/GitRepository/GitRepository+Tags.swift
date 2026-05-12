import Foundation

extension GitRepository: TagWritable {
    public func createTag(name: String, ref: String, message: String?) async throws {
        let result = try await commandRunner.run(.createTag(name: name, ref: ref, message: message))

        guard result.exitCode == 0 else {
            throw GitError.tagCreationFailed(name: name)
        }

        await cache.remove(.refs)
        eventSubject.send(.tagCreated(name: name))
    }

    public func deleteTag(name: String) async throws {
        let result = try await commandRunner.run(.deleteTag(name: name))

        guard result.exitCode == 0 else {
            throw GitError.tagDeletionFailed(name: name)
        }

        await cache.remove(.refs)
        eventSubject.send(.tagDeleted(name: name))
    }

    public func pushTag(name: String, remote: String = "origin") async throws {
        let result = try await backgroundRunner.run(.pushTag(remote: remote, name: name))

        guard result.exitCode == 0 else {
            let output = result.stderr + result.stdout
            if output.contains("authentication") || output.contains("denied") {
                throw GitError.authenticationFailed
            }
            throw GitError.pushFailed
        }

        eventSubject.send(.tagPushed(name: name, remote: remote))
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
        eventSubject.send(.tagDeleted(name: name))
    }
}
