//
//  Tree.swift
//  Odin
//
//  Created by Viktor Gidlöf on 2025-11-07.
//

import Foundation

public struct Tree: Sendable {
    let id: String
    let entries: [Entry]
    
    public struct Entry: Sendable {
        let mode: String
        let type: EntryType
        let hash: String
        let name: String
        let path: String // full path from root
        
        enum EntryType {
            case blob
            case tree
            case symlink
            case gitlink // submodule
        }
    }
}
