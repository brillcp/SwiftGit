import Foundation
import Synchronization

/// Fans `GitEvent`s out to any number of listeners without Combine.
///
/// Two ways in:
/// - `observe(_:)` registers a synchronous handler, called on the emitting
///   thread in registration order. Used by `GitRepository`'s tests, where
///   deterministic delivery matters.
/// - `subscribe()` returns an `AsyncStream` that receives every event sent
///   after the call until the consumer stops iterating or its task is
///   cancelled. Each subscriber gets its own stream, so several consumers
///   can listen independently. This is what `GitRepositoryProtocol.events()`
///   hands out.
///
/// `Sendable` by construction: the only state is a lock-protected handler
/// table, so an actor can hold one as a plain `let` and expose it from a
/// `nonisolated` member without any `unsafe` opt-outs.
final class GitEventPublisher: Sendable {
    typealias Handler = @Sendable (GitEvent) -> Void

    /// Handle returned by `observe(_:)`; call `cancel()` to stop receiving.
    struct Observation: Sendable {
        fileprivate let id: UUID
        fileprivate let publisher: GitEventPublisher

        func cancel() {
            publisher.remove(id)
        }
    }

    private let handlers = Mutex<[UUID: Handler]>([:])
    /// Delivery order follows registration order, which a dictionary alone
    /// would not guarantee.
    private let order = Mutex<[UUID]>([])

    init() {}

    @discardableResult
    func observe(_ handler: @escaping Handler) -> Observation {
        let id = UUID()
        handlers.withLock { $0[id] = handler }
        order.withLock { $0.append(id) }
        return Observation(id: id, publisher: self)
    }

    func subscribe() -> AsyncStream<GitEvent> {
        let (stream, continuation) = AsyncStream<GitEvent>.makeStream(bufferingPolicy: .unbounded)
        let observation = observe { event in
            continuation.yield(event)
        }
        continuation.onTermination = { _ in
            observation.cancel()
        }
        return stream
    }

    func send(_ event: GitEvent) {
        let ids = order.withLock { $0 }
        let table = handlers.withLock { $0 }
        for id in ids {
            table[id]?(event)
        }
    }

    private func remove(_ id: UUID) {
        handlers.withLock { _ = $0.removeValue(forKey: id) }
        order.withLock { $0.removeAll { $0 == id } }
    }
}
