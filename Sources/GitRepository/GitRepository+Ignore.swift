import Foundation

extension GitRepository: IgnoreWritable {
    public func ignore(pattern: String) async throws {
        let gitignoreURL = url.appendingPathComponent(".gitignore")

        var content = (try? String(contentsOf: gitignoreURL, encoding: .utf8)) ?? ""

        // Skip if already present
        let lines = content.components(separatedBy: .newlines)
        guard !lines.contains(pattern) else { return }

        if !content.isEmpty && !content.hasSuffix("\n") {
            content += "\n"
        }
        content += pattern + "\n"

        try content.write(to: gitignoreURL, atomically: true, encoding: .utf8)
    }
}
