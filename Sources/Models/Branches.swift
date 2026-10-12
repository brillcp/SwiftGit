import Foundation

public struct Branches: Equatable, Sendable {
    public let local: [GitRef]
    public let remote: [GitRef]
    public let current: String?

    public init(local: [GitRef], remote: [GitRef], current: String?) {
        self.local = local
        self.remote = remote
        self.current = current
    }
}