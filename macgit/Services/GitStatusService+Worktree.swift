import Foundation

enum WorktreeAddTarget: Sendable, Equatable {
    case existingBranch(String)
    case newBranch(name: String, base: String?)
}

extension GitStatusService {
    func worktrees(in repositoryURL: URL) async -> [WorktreeEntry] {
        let output = (try? await runGit(arguments: ["worktree", "list", "--porcelain"], in: repositoryURL)) ?? ""
        let parsed = parseWorktreePorcelain(output)

        var dirtyCounts: [URL: Int] = [:]
        await withTaskGroup(of: (URL, Int).self) { group in
            for entry in parsed {
                group.addTask {
                    let count = await self.dirtyCount(in: entry.path)
                    return (entry.path, count)
                }
            }

            for await (path, count) in group {
                dirtyCounts[path] = count
            }
        }

        return parsed.map { entry in
            WorktreeEntry(
                path: entry.path,
                head: entry.head,
                branch: entry.branch,
                isLocked: entry.isLocked,
                dirtyCount: dirtyCounts[entry.path] ?? -1,
                label: nil
            )
        }
    }

    func dirtyCount(in worktreePath: URL) async -> Int {
        guard let output = try? await runGit(arguments: ["status", "--porcelain"], in: worktreePath) else {
            return -1
        }

        return output.split(separator: "\n").count
    }

    func gitCommonDirectory(in repositoryURL: URL) async throws -> URL {
        let output = try await runGit(
            arguments: ["rev-parse", "--path-format=absolute", "--git-common-dir"],
            in: repositoryURL
        )
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedWorktreeURL(from: path)
    }

    func worktreesWithLabels(in repositoryURL: URL) async -> [WorktreeEntry] {
        let entries = await worktrees(in: repositoryURL)
        guard let gitDirectory = try? await gitCommonDirectory(in: repositoryURL) else {
            return entries
        }

        let store = WorktreeLabelStore()
        let labels = (try? store.prune(validPaths: Set(entries.map(\.path)), in: gitDirectory))
            ?? store.labels(in: gitDirectory)

        return entries.map { entry in
            var labeled = entry
            labeled.label = labels[WorktreeLabelStore.key(for: entry.path)]
            return labeled
        }
    }

    func setWorktreeLabel(_ label: String?, for path: URL, in repositoryURL: URL) async throws {
        let gitDirectory = try await gitCommonDirectory(in: repositoryURL)
        try WorktreeLabelStore().setLabel(label, for: path, in: gitDirectory)
        await postRepositoryDidChange(for: repositoryURL)
    }

    func removeWorktreeLabel(for path: URL, in repositoryURL: URL) async throws {
        let gitDirectory = try await gitCommonDirectory(in: repositoryURL)
        try WorktreeLabelStore().removeLabel(for: path, in: gitDirectory)
        await postRepositoryDidChange(for: repositoryURL)
    }

    func addWorktree(
        at path: URL,
        target: WorktreeAddTarget,
        label: String?,
        in repositoryURL: URL
    ) async throws {
        var arguments = ["worktree", "add"]
        switch target {
        case .existingBranch(let branch):
            arguments.append(path.path)
            arguments.append(branch)
        case .newBranch(let name, let base):
            arguments.append("-b")
            arguments.append(name)
            arguments.append(path.path)
            if let base, !base.isEmpty {
                arguments.append(base)
            }
        }

        _ = try await runGit(arguments: arguments, in: repositoryURL)

        if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let gitDirectory = try await gitCommonDirectory(in: repositoryURL)
            try WorktreeLabelStore().setLabel(label, for: path, in: gitDirectory)
        }

        await postRepositoryDidChange(for: repositoryURL)
    }

    func removeWorktree(at path: URL, force: Bool, in repositoryURL: URL) async throws {
        if isMainWorktree(path, repositoryURL: repositoryURL) {
            throw GitError.commandFailed("The main worktree cannot be removed.")
        }

        var arguments = ["worktree", "remove"]
        if force {
            arguments.append("--force")
        }
        arguments.append(path.path)

        _ = try await runGit(arguments: arguments, in: repositoryURL)

        let gitDirectory = try await gitCommonDirectory(in: repositoryURL)
        try WorktreeLabelStore().removeLabel(for: path, in: gitDirectory)
        await postRepositoryDidChange(for: repositoryURL)
    }

    private struct ParsedWorktree {
        let path: URL
        let head: String
        let branch: String?
        let isLocked: Bool
    }

    private func parseWorktreePorcelain(_ output: String) -> [ParsedWorktree] {
        var entries: [ParsedWorktree] = []
        var path: URL?
        var head = ""
        var branch: String?
        var isLocked = false

        func flushCurrentEntry() {
            guard let path else { return }
            entries.append(
                ParsedWorktree(
                    path: path,
                    head: String(head.prefix(7)),
                    branch: branch,
                    isLocked: isLocked
                )
            )
        }

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if line.isEmpty {
                flushCurrentEntry()
                path = nil
                head = ""
                branch = nil
                isLocked = false
                continue
            }

            if line.hasPrefix("worktree ") {
                flushCurrentEntry()
                path = normalizedWorktreeURL(from: String(line.dropFirst("worktree ".count)))
                head = ""
                branch = nil
                isLocked = false
            } else if line.hasPrefix("HEAD ") {
                head = String(line.dropFirst("HEAD ".count))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            } else if line == "locked" || line.hasPrefix("locked ") {
                isLocked = true
            }
        }

        flushCurrentEntry()

        return entries
    }

    private func normalizedWorktreeURL(from path: String) -> URL {
        let cleanPath = path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
        return URL(fileURLWithPath: cleanPath, isDirectory: false)
    }

    private func isMainWorktree(_ path: URL, repositoryURL: URL) -> Bool {
        normalizedWorktreePath(path) == normalizedWorktreePath(repositoryURL)
    }

    private func normalizedWorktreePath(_ url: URL) -> String {
        WorktreeLabelStore.key(for: url)
    }

    @MainActor
    private func postRepositoryDidChange(for repositoryURL: URL) {
        NotificationCenter.default.post(name: .repositoryDidChange, object: nil, userInfo: ["repositoryURL": repositoryURL])
    }
}
