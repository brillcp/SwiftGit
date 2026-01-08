import Foundation

public struct Tree: Sendable {
    public let id: String
    public let entries: [Entry]

    public init(id: String, entries: [Entry]) {
        self.id = id
        self.entries = entries
    }

    public struct Entry: Sendable {
        public let mode: String
        public let type: EntryType
        public let hash: String
        public let name: String
        public let path: String // full path from root

        public enum EntryType: Sendable {
            case blob
            case tree
            case symlink
            case gitlink
        }

        public init(mode: String, type: EntryType, hash: String, name: String, path: String) {
            self.mode = mode
            self.type = type
            self.hash = hash
            self.name = name
            self.path = path
        }
    }
}