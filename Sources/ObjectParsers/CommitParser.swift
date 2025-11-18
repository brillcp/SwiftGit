import Foundation

public protocol CommitParserProtocol: ObjectParserProtocol where Output == Commit {}

// MARK: -
public final class CommitParser {}

// MARK: - CommitParserProtocol
extension CommitParser: CommitParserProtocol {
    public func parse(hash: String, data: Data) throws -> Commit {
        // Check if data starts with valid commit markers
        guard let content = String(data: data, encoding: .utf8) else {
            throw ParseError.invalidEncoding
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        var tree = ""
        var parents: [String] = []
        var author: Author?
        var committer: Author?

        var messageLines: [String] = []
        var inMessage = false

        for line in lines {
            if inMessage {
                messageLines.append(String(line))
                continue
            }

            if line.isEmpty {
                inMessage = true
                continue
            }

            switch () {
            case _ where line.hasPrefix("tree "):
                tree = String(line.dropFirst(5))
            case _ where line.hasPrefix("parent "):
                parents.append(String(line.dropFirst(7)))
            case _ where line.hasPrefix("author "):
                author = String(line).parseAuthor()
            case _ where line.hasPrefix("committer "):
                committer = String(line).parseAuthor("committer ")
            default:
                break
            }
        }

        guard !tree.isEmpty,
              let author,
              let committer,
              !messageLines.isEmpty
        else {
            throw ParseError.malformedCommit
        }

        let title = messageLines.first ?? ""
        let body = messageLines.dropFirst().joined(separator: "\n").replacingOccurrences(of: "^\\n+", with: "", options: .regularExpression)

        return Commit(
            id: hash,
            title: title,
            body: body,
            author: author,
            parents: parents,
            tree: tree
        )
    }
}

// MARK: - Private author parser
private extension String {
    func parseAuthor(_ prefix: String = "author ") -> Author? {
        let raw = dropFirst(prefix.count)

        guard let emailStart = raw.firstIndex(of: "<"),
              let emailEnd = raw.firstIndex(of: ">")
        else { return nil }

        let name = raw[..<emailStart].trimmingCharacters(in: .whitespaces)
        let email = raw[raw.index(after: emailStart)..<emailEnd]
        let remainder = raw[emailEnd...].dropFirst().split(separator: " ")

        guard remainder.count >= 2 else { return nil }

        let timestampString = remainder[0]
        let timezoneString = remainder[1]

        guard let ts = TimeInterval(timestampString) else { return nil }

        return Author(
            name: name,
            email: String(email),
            timestamp: Date(timeIntervalSince1970: ts),
            timezone: String(timezoneString)
        )
    }
}
