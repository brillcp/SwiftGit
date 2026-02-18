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
}
