import Foundation

extension GitRepository: ObjectReadable {
    public func getTree(_ hash: String) async throws -> Tree? {
        if let cached: Tree = await cache.get(.tree(hash: hash)) { return cached }

        guard let parsedObject = try await loadObject(hash: hash),
              case .tree(let tree) = parsedObject
        else { return nil }

        await cache.set(.tree(hash: hash), value: tree)
        return tree
    }

    public func getTreePaths(_ treeHash: String) async throws -> [String : String] {
        if let cached: [String: String] = await cache.get(.treePaths(hash: treeHash)) { return cached }

        var paths: [String: String] = [:]

        try await walkTree(treeHash) { entry in
            if entry.type == .blob {
                paths[entry.path] = entry.hash
            }
            return true
        }

        await cache.set(.treePaths(hash: treeHash), value: paths)
        return paths
    }
}

// MARK: - Private helpers
private extension GitRepository {
    func walkTree(_ treeHash: String, visitor: (Tree.Entry) async throws -> Bool) async throws {
        try await walkTreeRecursive(treeHash: treeHash, currentPath: "", visitor: visitor)
    }

    func walkTreeRecursive(
        treeHash: String,
        currentPath: String,
        visitor: (Tree.Entry) async throws -> Bool
    ) async throws {
        guard let tree = try await getTree(treeHash) else { return }

        for entry in tree.entries {
            let fullPath = currentPath.isEmpty ? entry.name : "\(currentPath)/\(entry.name)"
            let entryType: Tree.Entry.EntryType

            if entry.mode.hasPrefix("40") || entry.mode == "040000" {
                entryType = .tree
            } else if entry.mode == "120000" {
                entryType = .symlink
            } else if entry.mode == "160000" {
                entryType = .gitlink
            } else {
                entryType = .blob
            }

            let treeEntry = Tree.Entry(
                mode: entry.mode,
                type: entryType,
                hash: entry.hash,
                name: entry.name,
                path: fullPath
            )

            let shouldContinue = try await visitor(treeEntry)
            if !shouldContinue {
                return
            }

            // Recurse into subdirectories
            if entryType == .tree {
                try await walkTreeRecursive(
                    treeHash: entry.hash,
                    currentPath: fullPath,
                    visitor: visitor
                )
            }
        }
    }
}
