import Foundation

public struct Blob: Hashable, Sendable {
    public let id: String
    public let data: Data

    public init(id: String, data: Data) {
        self.id = id
        self.data = data
    }
}

// MARK: -
extension Blob {
    public var text: String? { String(data: data, encoding: .utf8) }
    public var isImage: Bool { data.starts(with: [0x89,0x50,0x4E,0x47]) } // PNG
}