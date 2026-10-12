import Foundation
import Synchronization
import Testing
@testable import SwiftGit

@Suite("Git Event Tests")
struct GitEventTests {
    @Test func ordinaryMutationsEmitOneTerminalEvent() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        try createTestFile(in: repoURL, named: "file.txt", content: "initial\n")
        try await repository.stageFile(at: "file.txt")
        try await repository.commit(message: "Initial")

        try createTestFile(in: repoURL, named: "file.txt", content: "committed change\n")
        try await repository.stageFile(at: "file.txt")
        let commitEvents = try await recordEvents(from: repository) {
            try await repository.commit(message: "Second")
        }
        #expect(commitEvents.count == 1)
        guard case .committed = commitEvents.first else {
            Issue.record("Commit should emit only .committed")
            return
        }

        try createTestFile(in: repoURL, named: "file.txt", content: "stashed change\n")
        let stashEvents = try await recordEvents(from: repository) {
            try await repository.stashPush(message: "Event test")
        }
        #expect(stashEvents.count == 1)
        guard case .stashed = stashEvents.first else {
            Issue.record("Stash push should emit only .stashed")
            return
        }

        let dropEvents = try await recordEvents(from: repository) {
            try await repository.stashDrop(index: 0)
        }
        #expect(dropEvents.count == 1)
        guard case .stashDropped = dropEvents.first else {
            Issue.record("Stash drop should emit only .stashDropped")
            return
        }

        let branchEvents = try await recordEvents(from: repository) {
            try await repository.checkoutBranch("feature", createNew: true)
        }
        #expect(branchEvents.count == 1)
        guard case .branchChanged(name: "feature") = branchEvents.first else {
            Issue.record("Branch creation should emit only .branchChanged")
            return
        }

        let tagEvents = try await recordEvents(from: repository) {
            try await repository.createTag(name: "event-test", ref: "HEAD", message: nil)
        }
        #expect(tagEvents.count == 1)
        guard case .tagCreated(name: "event-test") = tagEvents.first else {
            Issue.record("Tag creation should emit only .tagCreated")
            return
        }
    }

    @Test func revertEmitsOneTerminalCompletionEvent() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        try createTestFile(in: repoURL, named: "file.txt", content: "initial\n")
        try await repository.stageFile(at: "file.txt")
        try await repository.commit(message: "Initial")

        try createTestFile(in: repoURL, named: "file.txt", content: "change to revert\n")
        try await repository.stageFile(at: "file.txt")
        try await repository.commit(message: "Change")
        let commitHash = try #require(await repository.getHEAD())

        let events = try await recordEvents(from: repository) {
            try await repository.revertCommit(commitHash)
        }

        #expect(events.count == 2)
        guard events.count == 2 else { return }
        guard case .startReverting(hash: commitHash) = events[0] else {
            Issue.record("Revert should begin with .startReverting")
            return
        }
        guard case .operationCompleted(operation: .revert, ref: commitHash) = events[1] else {
            Issue.record("Revert should finish with one .operationCompleted event")
            return
        }
    }

    @Test func dirtyCherryPickPublishesItsNestedStashOperationsInOrder() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        try createTestFile(in: repoURL, named: "base.txt", content: "base\n")
        try await repository.stageFile(at: "base.txt")
        try await repository.commit(message: "Initial")

        try await repository.checkoutBranch("feature", createNew: true)
        try createTestFile(in: repoURL, named: "feature.txt", content: "feature\n")
        try await repository.stageFile(at: "feature.txt")
        try await repository.commit(message: "Feature")
        let featureHash = try #require(await repository.getHEAD())
        try await repository.checkoutBranch("main", createNew: false)

        try createTestFile(in: repoURL, named: "local.txt", content: "local work\n")
        let events = try await recordEvents(from: repository) {
            try await repository.cherryPick(featureHash)
        }

        #expect(events.count == 4)
        guard events.count == 4 else { return }
        guard case .startCherryPicking = events[0] else {
            Issue.record("Cherry-pick should begin with .startCherryPicking")
            return
        }
        guard case .stashed = events[1] else {
            Issue.record("Dirty cherry-pick should publish its auto-stash")
            return
        }
        guard case .stashPopped = events[2] else {
            Issue.record("Dirty cherry-pick should publish restoration of its auto-stash")
            return
        }
        guard case .operationCompleted(operation: .cherryPick, ref: featureHash) = events[3] else {
            Issue.record("Cherry-pick should finish after restoring the auto-stash")
            return
        }
    }
}

@Test func eventStreamDeliversEventsAndStopsWhenTheConsumerLeaves() async throws {
    let publisher = GitEventPublisher()
    let stream = publisher.subscribe()
    var iterator = stream.makeAsyncIterator()

    publisher.send(.allFilesStaged)
    publisher.send(.allFilesUnstaged)

    guard case .allFilesStaged = await iterator.next() else {
        Issue.record("First buffered event should be .allFilesStaged")
        return
    }
    guard case .allFilesUnstaged = await iterator.next() else {
        Issue.record("Second buffered event should be .allFilesUnstaged")
        return
    }

    // A second subscriber only sees events sent after it subscribed.
    let late = publisher.subscribe()
    var lateIterator = late.makeAsyncIterator()
    publisher.send(.allFilesDiscarded)
    guard case .allFilesDiscarded = await lateIterator.next() else {
        Issue.record("Late subscriber should receive only the event sent after subscribing")
        return
    }
    guard case .allFilesDiscarded = await iterator.next() else {
        Issue.record("First subscriber should also receive the third event")
        return
    }
}

private func recordEvents(
    from repository: GitRepository,
    during operation: () async throws -> Void
) async throws -> [GitEvent] {
    // The synchronous observer, not the async stream: events are recorded
    // on the emitting thread, so everything the operation emitted is in the
    // array by the time it returns.
    let recordedEvents = Mutex<[GitEvent]>([])
    let observation = repository.eventPublisher.observe { event in
        recordedEvents.withLock { $0.append(event) }
    }

    try await operation()
    observation.cancel()
    return recordedEvents.withLock { $0 }
}
