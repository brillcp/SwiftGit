import Foundation

public struct WorkflowStep: Sendable {
    public let command: GitCommand
    public let mapError: @Sendable (CommandResult) -> GitError

    public init(
        command: GitCommand,
        mapError: @escaping @Sendable (CommandResult) -> GitError
    ) {
        self.command = command
        self.mapError = mapError
    }
}

public struct GitWorkflow: Sendable {
    public let name: String?
    public let steps: [WorkflowStep]
    public let onComplete: GitEvent?

    public init(
        name: String? = nil,
        steps: [WorkflowStep],
        onComplete: GitEvent? = nil
    ) {
        self.name = name
        self.steps = steps
        self.onComplete = onComplete
    }

    /// Backward-compatible initializer: flat commands with generic error
    public init(
        name: String? = nil,
        commands: [GitCommand],
        onComplete: GitEvent? = nil
    ) {
        let workflowName = name ?? "workflow"
        self.name = name
        self.steps = commands.map { cmd in
            WorkflowStep(command: cmd) { _ in
                .workflowFailed(name: workflowName)
            }
        }
        self.onComplete = onComplete
    }
}
