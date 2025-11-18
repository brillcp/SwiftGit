import Foundation

extension String {
    public var shortHash: String {
        String(prefix(6))
    }
}
