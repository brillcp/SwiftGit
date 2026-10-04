import Foundation

/// A single parsed line of progress from `git clone --progress`, e.g.
/// "Receiving objects:  45% (567890/1234567), 123.45 MiB | 5.67 MiB/s".
public struct CloneProgress: Sendable, Equatable {
    public let stage: String
    public let percent: Int?
    public let completed: Int?
    public let total: Int?

    public init(stage: String, percent: Int? = nil, completed: Int? = nil, total: Int? = nil) {
        self.stage = stage
        self.percent = percent
        self.completed = completed
        self.total = total
    }
}

extension CloneProgress {
    /// Parses a raw stderr line from `git clone --progress`. Git emits lines like:
    /// "remote: Counting objects: 100% (12345/12345), done." and
    /// "Receiving objects:  45% (567890/1234567), 123.45 MiB | 5.67 MiB/s"
    static func parse(line: String) -> CloneProgress? {
        var content = line.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }

        if content.hasPrefix("remote: ") {
            content.removeFirst("remote: ".count)
        }

        guard let colonIndex = content.firstIndex(of: ":") else {
            return CloneProgress(stage: content)
        }

        let stage = String(content[content.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
        let rest = String(content[content.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
        guard !stage.isEmpty else { return nil }

        var percent: Int?
        if let percentRange = rest.range(of: #"^\d+%"#, options: .regularExpression) {
            percent = Int(rest[percentRange].dropLast())
        }

        var completed: Int?
        var total: Int?
        if let countsRange = rest.range(of: #"\(\d[\d,]*/\d[\d,]*\)"#, options: .regularExpression) {
            let numbers = rest[countsRange]
                .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                .split(separator: "/")
            if numbers.count == 2 {
                completed = Int(numbers[0].replacingOccurrences(of: ",", with: ""))
                total = Int(numbers[1].replacingOccurrences(of: ",", with: ""))
            }
        }

        return CloneProgress(stage: stage, percent: percent, completed: completed, total: total)
    }
}
