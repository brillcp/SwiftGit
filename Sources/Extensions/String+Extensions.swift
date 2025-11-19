import Foundation

extension String {
    public var shortHash: String {
        String(prefix(6))
    }

    public var isValidSHA: Bool {
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        return count == 40 && CharacterSet(charactersIn: self).isSubset(of: hex)
    }
}
