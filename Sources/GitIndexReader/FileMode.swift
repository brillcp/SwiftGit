import Foundation

public enum FileMode: UInt32, Sendable {
    case regular = 0o100644     // Regular file
    case executable = 0o100755  // Executable file
    case symlink = 0o120000     // Symbolic link
    case gitlink = 0o160000     // Git submodule

    public var isExecutable: Bool {
        self == .executable
    }

    public var isSymlink: Bool {
        self == .symlink
    }

    public var isSubmodule: Bool {
        self == .gitlink
    }

    public init?(rawValue: UInt32) {
        // Mask to get the file type bits
        let type = rawValue & 0o170000
        switch type {
        case 0o100000:
            // Regular file - check executable bit
            self = (rawValue & 0o000111) != 0 ? .executable : .regular
        case 0o120000:
            self = .symlink
        case 0o160000:
            self = .gitlink
        default:
            return nil
        }
    }
}