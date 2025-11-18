import Foundation

protocol CommitParserProtocol: ObjectParserProtocol where Output == Commit {}

// MARK: -
final class CommitParser {}

// MARK: - CommitParserProtocol
extension CommitParser: CommitParserProtocol {
    func parse(hash: String, data: Data) throws -> Commit {
        // Check if data starts with valid commit markers
        guard let content = String(data: data, encoding: .utf8) else {
            throw ParseError.invalidEncoding
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)

        var tree = ""
        var parents: [String] = []
//        var author: Author?
//        var committer: Author?

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
//            case _ where line.hasPrefix("author "):
//                author = String(line).parseAuthor()
//            case _ where line.hasPrefix("committer "):
//                committer = String(line).parseAuthor("committer ")
            default:
                break
            }
        }

        guard !tree.isEmpty,
//              let author,
//              let committer,
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
//            author: author,
            parents: parents,
            tree: tree
        )
    }
}
