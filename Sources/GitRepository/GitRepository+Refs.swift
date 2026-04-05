import Foundation
import Collections

extension GitRepository: RefReadable {
    public func getRefs() async throws -> OrderedDictionary<String, [GitRef]> {
        try await refReader.getRefs()
    }

    public func getRemoteTagNames(remote: String = "origin") async throws -> Set<String> {
        let result = try await backgroundRunner.run(.lsRemoteTags(remote: remote))
        guard result.exitCode == 0 else { return [] }

        let prefix = "refs/tags/"
        var names = Set<String>()

        for line in result.stdout.split(separator: String.newLine) where !line.isEmpty {
            let parts = line.split(separator: String.tab, maxSplits: 1)
            guard parts.count == 2 else { continue }
            var refName = String(parts[1])
            if refName.hasPrefix(prefix) {
                refName = String(refName.dropFirst(prefix.count))
            }
            // Skip dereferenced tag refs (e.g., "v1.0^{}")
            if refName.hasSuffix("^{}") { continue }
            names.insert(refName)
        }

        return names
    }
}
