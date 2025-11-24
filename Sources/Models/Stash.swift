import Foundation

public struct Stash: Sendable, Identifiable {
    public let id: String
    public let index: Int
    public let message: String
    public let date: Date

    public init(id: String, index: Int, message: String, date: Date) {
        self.id = id
        self.index = index
        self.message = message
        self.date = date
    }
}
