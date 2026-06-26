import Foundation

struct WorktreeLabelStore {
    nonisolated init() {}

    nonisolated func labels(in gitCommonDirectory: URL) -> [String: String] {
        let url = labelsURL(in: gitCommonDirectory)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }

        return decoded
    }

    nonisolated func label(for path: URL, in gitCommonDirectory: URL) -> String? {
        labels(in: gitCommonDirectory)[Self.key(for: path)]
    }

    nonisolated func setLabel(_ label: String?, for path: URL, in gitCommonDirectory: URL) throws {
        var current = labels(in: gitCommonDirectory)
        let trimmed = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            current.removeValue(forKey: Self.key(for: path))
        } else {
            current[Self.key(for: path)] = trimmed
        }

        try write(current, in: gitCommonDirectory)
    }

    nonisolated func removeLabel(for path: URL, in gitCommonDirectory: URL) throws {
        var current = labels(in: gitCommonDirectory)
        current.removeValue(forKey: Self.key(for: path))
        try write(current, in: gitCommonDirectory)
    }

    nonisolated func moveLabel(from oldPath: URL, to newPath: URL, in gitCommonDirectory: URL) throws {
        var current = labels(in: gitCommonDirectory)
        let oldKey = Self.key(for: oldPath)

        guard let label = current.removeValue(forKey: oldKey) else {
            try write(current, in: gitCommonDirectory)
            return
        }

        current[Self.key(for: newPath)] = label
        try write(current, in: gitCommonDirectory)
    }

    @discardableResult
    nonisolated func prune(validPaths: Set<URL>, in gitCommonDirectory: URL) throws -> [String: String] {
        let validKeys = Set(validPaths.map(Self.key(for:)))
        let current = labels(in: gitCommonDirectory)
        let pruned = current.filter { validKeys.contains($0.key) }

        if pruned != current {
            try write(pruned, in: gitCommonDirectory)
        }

        return pruned
    }

    nonisolated static func key(for path: URL) -> String {
        var normalized = path.standardizedFileURL.path
        if normalized.hasPrefix("/private/") {
            normalized = String(normalized.dropFirst("/private".count))
        }
        return normalized
    }

    private nonisolated func labelsURL(in gitCommonDirectory: URL) -> URL {
        gitCommonDirectory
            .appendingPathComponent("macgit", isDirectory: true)
            .appendingPathComponent("worktree-labels.json")
    }

    private nonisolated func write(_ labels: [String: String], in gitCommonDirectory: URL) throws {
        let url = labelsURL(in: gitCommonDirectory)
        let fileManager = FileManager()
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(labels)
        try data.write(to: url, options: .atomic)
    }
}
