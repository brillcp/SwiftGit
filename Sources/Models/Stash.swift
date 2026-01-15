import Foundation

public struct Stash: Identifiable, Sendable {
    public var id: String { hash }
    public let hash: String
    public let index: Int
    public let message: String
    public let date: Date

    public init(hash: String, index: Int, message: String, date: Date) {
        self.hash = hash
        self.index = index
        self.message = message
        self.date = date
    }
}
