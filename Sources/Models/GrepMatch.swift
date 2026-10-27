import Foundation

/// One line `git grep` matched.
public struct GrepMatch: Sendable, Equatable {
    public let path: String
    /// 1-based.
    public let line: Int
    public let text: String

    public init(path: String, line: Int, text: String) {
        self.path = path
        self.line = line
        self.text = text
    }
}

extension GrepMatch {
    /// Parses `git grep -n --null` output. With a ref, git prefixes each path
    /// with `<ref>:`, which is stripped.
    static func parse(_ output: String, ref: String?) -> [GrepMatch] {
        let refPrefix = ref.map { "\($0):" }
        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { record in
            // path \0 line \0 text
            let fields = record.split(separator: Character(String.null), maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, let line = Int(fields[1]) else { return nil }
            var path = String(fields[0])
            if let refPrefix, path.hasPrefix(refPrefix) {
                path.removeFirst(refPrefix.count)
            }
            return GrepMatch(path: path, line: line, text: String(fields[2]))
        }
    }
}
