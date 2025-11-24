import Foundation

public struct Stash: Sendable, Identifiable {
    public let id: String
    public let index: Int
    public let message: String
    public let date: Date
}
