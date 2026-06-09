import Foundation

extension GitRepository: IgnoreWritable {
    public func ignore(pattern: String) async throws {
        let gitignoreURL = url.appendingPathComponent(".gitignore")

        var content = (try? String(contentsOf: gitignoreURL, encoding: .utf8)) ?? ""

        // Skip if already present
        let lines = content.components(separatedBy: .newlines)
        guard !lines.contains(pattern) else { return }

        if !content.isEmpty && !content.hasSuffix(String.newLine) {
            content += String.newLine
        }
        content += pattern + String.newLine

        try content.write(to: gitignoreURL, atomically: true, encoding: .utf8)
        await workingTree.invalidateIndexCache()
        eventSubject.send(.ignoreUpdated(pattern: pattern))
    }
}
