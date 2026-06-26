import Testing
import Foundation
@testable import SwiftGit

@Suite("Conflict Resolution Tests")
struct ConflictTests {

    // MARK: - Merge Conflicts

    @Test func testMergeConflictDetection() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Setup: create conflicting branches
        try await setupConflictingBranches(in: repoURL, repository: repository)

        // Attempt merge - should throw conflict error
        do {
            try await repository.merge(branch: "feature", noFastForward: true)
            Issue.record("Expected merge to throw conflict error")
        } catch let error as GitError {
            switch error {
            case .conflictDetected:
                break // expected
            default:
                Issue.record("Unexpected error: \(error)")
            }
        }

        // Verify conflict state
        let hasConflicts = !(try await repository.getConflictedFiles().isEmpty)
        #expect(hasConflicts == true, "Should have conflicts after failed merge")

        let operation = await repository.conflictOperation()
        #expect(operation == .merge, "Operation should be merge")

        let conflictedFiles = try await repository.getConflictedFiles()
        #expect(conflictedFiles.contains("conflict.txt"), "conflict.txt should be in conflict")
    }

    @Test func testMergeAbort() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Setup conflicting merge
        try await setupConflictingBranches(in: repoURL, repository: repository)
        try? await repository.merge(branch: "feature", noFastForward: true)

        // Verify we're in conflict state
        #expect(!(try await repository.getConflictedFiles().isEmpty) == true)

        // Abort merge
        try await repository.abortOperation()

        // Verify conflict state is cleared
        let hasConflicts = !(try await repository.getConflictedFiles().isEmpty)
        #expect(hasConflicts == false, "Should have no conflicts after abort")

        let operation = await repository.conflictOperation()
        #expect(operation == nil, "No operation should be in progress")
    }

    @Test func testMergeContinue() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Setup conflicting merge
        try await setupConflictingBranches(in: repoURL, repository: repository)
        try? await repository.merge(branch: "feature", noFastForward: true)

        // Resolve conflict manually
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Resolved content")
        try await repository.stageFile(at: "conflict.txt")

        // Continue merge
        try await repository.continueOperation()

        // Verify merge completed
        let hasConflicts = !(try await repository.getConflictedFiles().isEmpty)
        #expect(hasConflicts == false)

        let operation = await repository.conflictOperation()
        #expect(operation == nil)
    }

    // MARK: - Cherry-Pick Conflicts

    @Test func testCherryPickConflictDetection() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Setup: create commit to cherry-pick that will conflict
        let cherryPickHash = try await setupCherryPickConflict(in: repoURL, repository: repository)

        // Attempt cherry-pick - should throw conflict error
        do {
            try await repository.cherryPick(cherryPickHash)
            Issue.record("Expected cherry-pick to throw conflict error")
        } catch let error as GitError {
            switch error {
            case .cherryPickConflict:
                break // expected
            default:
                Issue.record("Unexpected error: \(error)")
            }
        }

        // Verify conflict state
        let hasConflicts = !(try await repository.getConflictedFiles().isEmpty)
        #expect(hasConflicts == true)

        let operation = await repository.conflictOperation()
        #expect(operation == .cherryPick)
    }

    @Test func testCherryPickAbort() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        let cherryPickHash = try await setupCherryPickConflict(in: repoURL, repository: repository)
        try? await repository.cherryPick(cherryPickHash)

        #expect(!(try await repository.getConflictedFiles().isEmpty) == true)

        try await repository.abortOperation()

        #expect(!(try await repository.getConflictedFiles().isEmpty) == false)
        #expect(await repository.conflictOperation() == nil)
    }

    @Test func testCherryPickContinue() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        let cherryPickHash = try await setupCherryPickConflict(in: repoURL, repository: repository)
        try? await repository.cherryPick(cherryPickHash)

        // Resolve conflict
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Resolved")
        try await repository.stageFile(at: "conflict.txt")

        try await repository.continueOperation()

        #expect(!(try await repository.getConflictedFiles().isEmpty) == false)
        #expect(await repository.conflictOperation() == nil)
    }

    @Test func testEmptyCherryPickIsSkipped() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        try createTestFile(in: repoURL, named: "already-applied.txt", content: "base")
        try await repository.stageFile(at: "already-applied.txt")
        try await repository.commit(message: "Initial commit")

        try await repository.checkoutBranch("feature", createNew: true)
        try createTestFile(in: repoURL, named: "already-applied.txt", content: "same change")
        try await repository.stageFile(at: "already-applied.txt")
        try await repository.commit(message: "Feature applies same change")

        guard let featureHash = try await repository.getHEAD() else {
            throw TestError.noHead
        }

        try await repository.checkoutBranch("main", createNew: false)
        try createTestFile(in: repoURL, named: "already-applied.txt", content: "same change")
        try await repository.stageFile(at: "already-applied.txt")
        try await repository.commit(message: "Main already has same change")

        let headBeforeCherryPick = try await repository.getHEAD()

        try await repository.cherryPick(featureHash)

        let headAfterCherryPick = try await repository.getHEAD()
        let status = try await repository.getWorkingTreeStatus()

        #expect(headAfterCherryPick == headBeforeCherryPick)
        #expect(status.files.isEmpty)
        #expect(await repository.conflictOperation() == nil)
        #expect((try await repository.getConflictedFiles()).isEmpty)
    }

    // MARK: - Revert Conflicts

    @Test func testRevertConflictDetection() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Setup: create a scenario where revert will conflict
        let revertHash = try await setupRevertConflict(in: repoURL, repository: repository)

        // Attempt revert - should throw conflict error
        do {
            try await repository.revertCommit(revertHash)
            Issue.record("Expected revert to throw conflict error")
        } catch let error as GitError {
            switch error {
            case .revertConflict:
                break // expected
            default:
                Issue.record("Unexpected error: \(error)")
            }
        }

        let hasConflicts = !(try await repository.getConflictedFiles().isEmpty)
        #expect(hasConflicts == true)

        let operation = await repository.conflictOperation()
        #expect(operation == .revert)
    }

    @Test func testRevertAbort() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        let revertHash = try await setupRevertConflict(in: repoURL, repository: repository)
        try? await repository.revertCommit(revertHash)

        #expect(!(try await repository.getConflictedFiles().isEmpty) == true)

        try await repository.abortOperation()

        #expect(!(try await repository.getConflictedFiles().isEmpty) == false)
        #expect(await repository.conflictOperation() == nil)
    }

    @Test func testRevertContinue() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        let revertHash = try await setupRevertConflict(in: repoURL, repository: repository)
        try? await repository.revertCommit(revertHash)

        // Resolve conflict
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Resolved after revert")
        try await repository.stageFile(at: "conflict.txt")

        try await repository.continueOperation()

        #expect(!(try await repository.getConflictedFiles().isEmpty) == false)
        #expect(await repository.conflictOperation() == nil)
    }

    // MARK: - Rebase Conflicts

    @Test func testRebaseConflictDetection() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Setup: create conflicting branches for rebase
        try await setupRebaseConflict(in: repoURL, repository: repository)

        // Attempt rebase - should throw conflict error
        do {
            try await repository.rebase(onto: "main")
            Issue.record("Expected rebase to throw conflict error")
        } catch let error as GitError {
            switch error {
            case .rebaseConflict:
                break // expected
            default:
                Issue.record("Unexpected error: \(error)")
            }
        }

        let hasConflicts = !(try await repository.getConflictedFiles().isEmpty)
        #expect(hasConflicts == true)

        let operation = await repository.conflictOperation()
        #expect(operation == .rebase)
    }

    @Test func testRebaseAbort() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        try await setupRebaseConflict(in: repoURL, repository: repository)
        try? await repository.rebase(onto: "main")

        #expect(!(try await repository.getConflictedFiles().isEmpty) == true)

        try await repository.abortOperation()

        #expect(!(try await repository.getConflictedFiles().isEmpty) == false)
        #expect(await repository.conflictOperation() == nil)
    }

    @Test func testRebaseSkip() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Initial commit on main
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Initial content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Initial commit")

        // Create feature branch with two commits — both will conflict so we can skip the first
        try await repository.checkoutBranch("feature", createNew: true)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Feature commit 1")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Feature commit 1")

        try createTestFile(in: repoURL, named: "other.txt", content: "Non-conflicting")
        try await repository.stageFile(at: "other.txt")
        try await repository.commit(message: "Feature commit 2")

        // Make main diverge so rebase produces a conflict on the first commit
        try await repository.checkoutBranch("main", createNew: false)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Main content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Main commit")

        // Switch to feature and start the rebase — expect conflict on commit 1
        try await repository.checkoutBranch("feature", createNew: false)
        try? await repository.rebase(onto: "main")

        #expect(await repository.conflictOperation() == .rebase)

        // Skip the conflicting commit instead of resolving it
        try await repository.skipOperation()

        // After skip the rebase should complete (commit 2 has no conflict)
        #expect(await repository.conflictOperation() == nil)
    }

    @Test func testRebaseContinue() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        try await setupRebaseConflict(in: repoURL, repository: repository)
        try? await repository.rebase(onto: "main")

        // Resolve conflict
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Resolved for rebase")
        try await repository.stageFile(at: "conflict.txt")

        try await repository.continueOperation()

        #expect(!(try await repository.getConflictedFiles().isEmpty) == false)
        #expect(await repository.conflictOperation() == nil)
    }

    // MARK: - Edge Cases

    @Test func testNoConflictOperationWhenClean() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Create a simple commit
        try createTestFile(in: repoURL, named: "file.txt", content: "Content")
        try await repository.stageFile(at: "file.txt")
        try await repository.commit(message: "Initial commit")

        let hasConflicts = !(try await repository.getConflictedFiles().isEmpty)
        #expect(hasConflicts == false)

        let operation = await repository.conflictOperation()
        #expect(operation == nil)

        let conflictedFiles = try await repository.getConflictedFiles()
        #expect(conflictedFiles.isEmpty)
    }

    @Test func testConflictOperationPriority() async throws {
        // Tests that conflictOperation returns the correct type
        // when checking file existence order
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Setup and trigger merge conflict
        try await setupConflictingBranches(in: repoURL, repository: repository)
        try? await repository.merge(branch: "feature", noFastForward: true)

        // Verify it's detected as merge (first in priority)
        let operation = await repository.conflictOperation()
        #expect(operation == .merge)
    }

    // MARK: - Conflict File Content (base, ours, theirs)

    @Test func testGetConflictVersions() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Setup: create conflicting branches with known content
        // Initial commit (will be "base")
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Base content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Initial commit")

        // Create feature branch with "theirs" content
        try await repository.checkoutBranch("feature", createNew: true)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Theirs content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Feature change")

        // Go back to main and create "ours" content
        try await repository.checkoutBranch("main", createNew: false)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Ours content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Main change")

        // Trigger merge conflict
        try? await repository.merge(branch: "feature", noFastForward: true)

        // Verify we're in conflict state
        #expect(!(try await repository.getConflictedFiles().isEmpty) == true)

        // Get the three versions using stage numbers:
        // :1: = base (common ancestor)
        // :2: = ours (current branch - main)
        // :3: = theirs (branch being merged - feature)

        let baseContent = try await repository.getFileContent(at: "conflict.txt", ref: ":1")
        #expect(baseContent == "Base content", "Base should be the common ancestor")

        let oursContent = try await repository.getFileContent(at: "conflict.txt", ref: ":2")
        #expect(oursContent == "Ours content", "Ours should be the current branch content")

        let theirsContent = try await repository.getFileContent(at: "conflict.txt", ref: ":3")
        #expect(theirsContent == "Theirs content", "Theirs should be the merged branch content")
    }

    @Test func testGetConflictVersionsForCherryPick() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Initial commit (base)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Base content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Initial commit")

        // Create feature branch with change
        try await repository.checkoutBranch("feature", createNew: true)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Cherry-pick content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Feature commit")

        guard let cherryHash = try await repository.getHEAD() else {
            throw TestError.noHead
        }

        // Go back to main and make conflicting change
        try await repository.checkoutBranch("main", createNew: false)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Main content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Main commit")

        // Trigger cherry-pick conflict
        try? await repository.cherryPick(cherryHash)

        #expect(!(try await repository.getConflictedFiles().isEmpty) == true)

        // For cherry-pick:
        // :1: = base (parent of cherry-picked commit)
        // :2: = ours (current HEAD)
        // :3: = theirs (cherry-picked commit)

        let baseContent = try await repository.getFileContent(at: "conflict.txt", ref: ":1")
        #expect(baseContent == "Base content")

        let oursContent = try await repository.getFileContent(at: "conflict.txt", ref: ":2")
        #expect(oursContent == "Main content")

        let theirsContent = try await repository.getFileContent(at: "conflict.txt", ref: ":3")
        #expect(theirsContent == "Cherry-pick content")
    }

    // MARK: - Branch name accessors (theirsBranchName / rebaseHeadName / rebaseOnto)

    @Test func testTheirsBranchNameDuringMerge() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        try await setupConflictingBranches(in: repoURL, repository: repository)

        // Trigger merge — expected to land in a conflicted state.
        try? await repository.merge(branch: "feature", noFastForward: true)
        #expect(await repository.conflictOperation() == .merge)

        let theirs = await repository.theirsBranchName()
        #expect(theirs == "feature", "MERGE_MSG should yield the merged-in branch name")
    }

    @Test func testTheirsBranchNameStripsRemotePrefix() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        try await setupConflictingBranches(in: repoURL, repository: repository)

        // Trigger a real merge to create MERGE_HEAD (so conflictOperation == .merge),
        // then overwrite MERGE_MSG with a remote-tracking shape to test the parser
        // strips `origin/` and returns the bare branch name.
        try? await repository.merge(branch: "feature", noFastForward: true)
        #expect(await repository.conflictOperation() == .merge)

        let mergeMsg = repoURL
            .appendingPathComponent(GitPath.git.rawValue)
            .appendingPathComponent(GitPath.mergeMsg.rawValue)
        try "Merge remote-tracking branch 'origin/feature' into main\n"
            .write(to: mergeMsg, atomically: true, encoding: .utf8)

        let theirs = await repository.theirsBranchName()
        #expect(theirs == "feature", "Parser should drop the `origin/` prefix")
    }

    @Test func testTheirsBranchNameDuringRebase() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        try await setupRebaseConflict(in: repoURL, repository: repository)

        try? await repository.rebase(onto: "main")
        #expect(await repository.conflictOperation() == .rebase)

        let theirs = await repository.theirsBranchName()
        #expect(theirs == "feature", "Rebase should expose the branch being rebased")
    }

    @Test func testTheirsBranchNameForCherryPickIsNil() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let hash = try await setupCherryPickConflict(in: repoURL, repository: repository)
        try? await repository.cherryPick(hash)
        #expect(await repository.conflictOperation() == .cherryPick)

        let theirs = await repository.theirsBranchName()
        #expect(theirs == nil, "Cherry-pick targets a commit, not a branch")
    }

    @Test func testTheirsBranchNameForRevertIsNil() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let hash = try await setupRevertConflict(in: repoURL, repository: repository)
        try? await repository.revertCommit(hash)
        #expect(await repository.conflictOperation() == .revert)

        let theirs = await repository.theirsBranchName()
        #expect(theirs == nil, "Revert targets a commit, not a branch")
    }

    @Test func testTheirsBranchNameWhenCleanIsNil() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        try createTestFile(in: repoURL, named: "file.txt", content: "Content")
        try await repository.stageFile(at: "file.txt")
        try await repository.commit(message: "Initial commit")

        #expect(await repository.theirsBranchName() == nil)
        #expect(await repository.rebaseHeadName() == nil)
        #expect(await repository.rebaseOnto() == nil)
    }

    @Test func testRebaseHeadNameAndOntoDuringRebase() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        try await setupRebaseConflict(in: repoURL, repository: repository)

        // Capture main's HEAD before starting the rebase — that's the commit
        // `.git/rebase-merge/onto` should reference.
        try await repository.checkoutBranch("main", createNew: false)
        guard let mainHash = try await repository.getHEAD() else {
            throw TestError.noHead
        }
        try await repository.checkoutBranch("feature", createNew: false)

        try? await repository.rebase(onto: "main")
        #expect(await repository.conflictOperation() == .rebase)

        let head = await repository.rebaseHeadName()
        #expect(head == "feature", "head-name should be the branch being rebased")

        let onto = await repository.rebaseOnto()
        #expect(onto == mainHash, "onto should point at main's tip commit")
    }

    @Test func testRebaseHeadNameAndOntoNilWhenNotRebasing() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        try await setupConflictingBranches(in: repoURL, repository: repository)

        // Active state is a merge, not a rebase — rebase fields stay nil.
        try? await repository.merge(branch: "feature", noFastForward: true)
        #expect(await repository.conflictOperation() == .merge)

        #expect(await repository.rebaseHeadName() == nil)
        #expect(await repository.rebaseOnto() == nil)
    }

    @Test func testGetConflictVersionsForRebase() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Initial commit (base)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Base content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Initial commit")

        // Create feature branch with change
        try await repository.checkoutBranch("feature", createNew: true)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Feature content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Feature commit")

        // Go back to main and make conflicting change
        try await repository.checkoutBranch("main", createNew: false)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Main content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Main commit")

        // Switch to feature and rebase onto main
        try await repository.checkoutBranch("feature", createNew: false)
        try? await repository.rebase(onto: "main")

        #expect(!(try await repository.getConflictedFiles().isEmpty) == true)

        // For rebase:
        // :1: = base (common ancestor)
        // :2: = ours (the branch we're rebasing onto - main)
        // :3: = theirs (the commit being rebased - feature)

        let baseContent = try await repository.getFileContent(at: "conflict.txt", ref: ":1")
        #expect(baseContent == "Base content")

        let oursContent = try await repository.getFileContent(at: "conflict.txt", ref: ":2")
        #expect(oursContent == "Main content", "During rebase, 'ours' is the target branch")

        let theirsContent = try await repository.getFileContent(at: "conflict.txt", ref: ":3")
        #expect(theirsContent == "Feature content", "During rebase, 'theirs' is the commit being rebased")
    }
}

// MARK: - Test Helpers

private extension ConflictTests {
    /// Creates two branches with conflicting changes to the same file
    func setupConflictingBranches(in repoURL: URL, repository: GitRepository) async throws {
        // Initial commit on main
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Initial content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Initial commit")

        // Create feature branch with different content
        try await repository.checkoutBranch("feature", createNew: true)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Feature branch content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Feature change")

        // Go back to main and make conflicting change
        try await repository.checkoutBranch("main", createNew: false)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Main branch content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Main change")
    }

    /// Creates a commit on a branch that will conflict when cherry-picked to main
    func setupCherryPickConflict(in repoURL: URL, repository: GitRepository) async throws -> String {
        // Initial commit on main
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Initial content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Initial commit")

        // Create feature branch with change
        try await repository.checkoutBranch("feature", createNew: true)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Feature content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Feature commit")

        guard let featureHash = try await repository.getHEAD() else {
            throw TestError.noHead
        }

        // Go back to main and make conflicting change
        try await repository.checkoutBranch("main", createNew: false)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Main content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Main commit")

        return featureHash
    }

    /// Creates a scenario where reverting a commit will conflict
    func setupRevertConflict(in repoURL: URL, repository: GitRepository) async throws -> String {
        // Initial commit
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Line 1\nLine 2\nLine 3")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Initial commit")

        // Commit to revert - changes line 2
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Line 1\nModified Line 2\nLine 3")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Change line 2")

        guard let revertHash = try await repository.getHEAD() else {
            throw TestError.noHead
        }

        // Another commit that also modifies line 2 differently
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Line 1\nDifferent Line 2\nLine 3")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Different change to line 2")

        return revertHash
    }

    /// Creates branches where rebasing will cause conflicts
    func setupRebaseConflict(in repoURL: URL, repository: GitRepository) async throws {
        // Initial commit on main
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Initial content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Initial commit")

        // Create feature branch with change
        try await repository.checkoutBranch("feature", createNew: true)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Feature content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Feature commit")

        // Go back to main and make conflicting change
        try await repository.checkoutBranch("main", createNew: false)
        try createTestFile(in: repoURL, named: "conflict.txt", content: "Main content")
        try await repository.stageFile(at: "conflict.txt")
        try await repository.commit(message: "Main commit")

        // Switch back to feature for rebase
        try await repository.checkoutBranch("feature", createNew: false)
    }
}

private enum TestError: Error {
    case noHead
}
