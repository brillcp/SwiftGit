//
//  Tree.swift
//  Odin
//
//  Created by Viktor Gidlöf on 2025-11-07.
//

import Foundation

public struct Tree: Sendable {
    public let id: String
    public let entries: [Entry]
    
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
            case gitlink // submodule
        }
    }
}
