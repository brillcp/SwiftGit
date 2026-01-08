import Foundation

extension String {
    public var shortHash: String {
        String(prefix(6))
    }

    public var isValidSHA: Bool {
        // SHA-1 is 40 hex characters, SHA-256 is 64
        let validLengths = [40, 64]
        guard validLengths.contains(count) else { return false }
        return allSatisfy { $0.isHexDigit }
    }

    public static let newLine: String = "\n"
}