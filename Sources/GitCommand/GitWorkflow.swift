import Foundation

public struct GitWorkflow: Sendable {
    public let name: String?
    public let commands: [GitCommand]
    public let onComplete: GitEvent

    public init(
        name: String? = nil,
        commands: [GitCommand],
        onComplete: GitEvent
    ) {
        self.name = name
        self.commands = commands
        self.onComplete = onComplete
    }
}
