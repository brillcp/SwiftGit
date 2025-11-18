import Foundation

public struct Branches {
    public let local: [GitRef]
    public let remote: [GitRef]
    public let current: String?
}
