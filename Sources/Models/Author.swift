import Foundation

public struct Author: Sendable {
    public let name: String
    public let email: String
    public let timestamp: Date
    public let timezone: String

    public init(name: String, email: String, timestamp: Date, timezone: String) {
        self.name = name
        self.email = email
        self.timestamp = timestamp
        self.timezone = timezone
    }
}