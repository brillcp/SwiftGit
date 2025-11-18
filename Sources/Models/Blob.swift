import Foundation

public struct Blob: Sendable {
    let id: String
    let data: Data
}

// MARK: -
public extension Blob {
    var text: String? { String(data: data, encoding: .utf8) }
    var isImage: Bool { data.starts(with: [0x89,0x50,0x4E,0x47]) } // PNG
}
