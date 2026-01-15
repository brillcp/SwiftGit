import Foundation

extension GitRepository: CherryPickWritable {
    public func cherryPick(_ commitHash: String) async throws {
        let result = try await commandRunner.run(
            .cherryPick(commitHash: commitHash),
            stdin: nil
        )

        if result.exitCode != 0 {
            let conflict = "conflict"
            if result.stderr.contains(conflict) || result.stderr.contains(conflict.uppercased()) {
                throw GitError.cherryPickConflict(commit: commitHash)
            }
            throw GitError.cherryPickFailed(commit: commitHash)
        }

        await invalidateAllCaches()
    }
}
