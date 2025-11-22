//
//  GitChangeType.swift
//  SwiftGit
//
//  Created by Viktor Gidlöf on 2025-11-21.
//

import Foundation

public enum GitChangeType: Hashable, Sendable {
    case added
    case modified
    case deleted
    case renamed(from: String)
    case untracked
}
