import Foundation

public struct GitWorkflow {
    let name: String?
    let commands: [GitCommand]
    let onComplete: GitEvent?

    public init(name: String? = nil, commands: [GitCommand], onComplete: GitEvent? = nil) {
        self.name = name
        self.commands = commands
        self.onComplete = onComplete
    }
}
